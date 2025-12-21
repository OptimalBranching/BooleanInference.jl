#include "cadical.hpp"
#include <cstdint>
#include <vector>
#include <cstring>
#include <cstdlib>

using namespace CaDiCaL;

// Collect learned clauses (filter by length only; LBD is not available in this Learner API)
struct Collector : public Learner {
  std::vector<std::vector<int32_t>> clauses;
  int32_t max_len;

  int32_t expected = 0;
  bool accept = true;
  bool done = false;
  std::vector<int32_t> cur;

  Collector(int32_t max_len_) : max_len(max_len_) {}

  // Called once per learned clause with its size.
  bool learning(int size) override {
    expected = size;
    cur.clear();
    done = false;

    accept = (max_len <= 0) ? true : (size <= max_len);
    if (accept) cur.reserve((size_t)size);

    // If false, CaDiCaL will skip calling learn(lit) for this clause.
    return accept;
  }

  // Called `size` times, each time with one literal.
  void learn(int lit) override {
    if (!accept) return;

    // Be robust in case a terminating 0 is passed.
    if (lit == 0) {
      if (!done && (int)cur.size() == expected) {
        clauses.push_back(cur);
        done = true;
      }
      return;
    }

    cur.push_back((int32_t)lit);

    // Finalize once we have collected all literals.
    if (!done && (int)cur.size() == expected) {
      clauses.push_back(cur);
      done = true;
    }
  }
};

extern "C" {

// Return learned clauses in a flattened form:
// - out_lits: all literals concatenated
// - out_offsets: offsets per clause (length = num_clauses+1), so clause i is
//   out_lits[offsets[i] : offsets[i+1]-1]
//
// Caller must free out_lits and out_offsets using free().
int cadical_mine_learned_cnf(
    // CNF input in flattened form: in_offsets length = nclauses+1
    const int32_t* in_lits,
    const int32_t* in_offsets,
    int32_t nclauses,
    int32_t nvars,
    // limits
    int32_t conflict_limit,
    int32_t max_len,
    int32_t max_lbd,
    // outputs
    int32_t** out_lits,
    int32_t** out_offsets,
    int32_t* out_nclauses,
    int32_t* out_nlits
) {
  Solver s;

  s.reserve(nvars);

  // feed CNF
  for (int32_t i = 0; i < nclauses; ++i) {
    int32_t a = in_offsets[i];
    int32_t b = in_offsets[i+1];
    for (int32_t k = a; k < b; ++k) s.add((int)in_lits[k]);
    s.add(0);
  }

  (void)max_lbd; // LBD filtering not supported by this Learner interface
  Collector col(max_len);
  s.connect_learner(&col);

  // Conflict limits are per-solve in CaDiCaL.
  if (conflict_limit > 0) s.limit("conflicts", conflict_limit);

  s.solve(); // returns 10/20/0, we don't care; we want learned clauses so far

  // flatten output
  int32_t m = (int32_t)col.clauses.size();
  std::vector<int32_t> offsets(m + 1, 0);
  int64_t total = 0;
  for (int32_t i = 0; i < m; ++i) {
    offsets[i] = (int32_t)total;
    total += (int32_t)col.clauses[i].size();
  }
  offsets[m] = (int32_t)total;

  std::vector<int32_t> lits;
  lits.reserve((size_t)total);
  for (auto &c : col.clauses) lits.insert(lits.end(), c.begin(), c.end());

  // allocate with malloc so Julia can free() via Libc.free
  *out_nclauses = m;
  *out_nlits = (int32_t)lits.size();

  *out_offsets = (int32_t*)malloc(sizeof(int32_t) * (m + 1));
  *out_lits    = (int32_t*)malloc(sizeof(int32_t) * (size_t)lits.size());
  if (!*out_offsets || (!*out_lits && !lits.empty())) return 0;

  memcpy(*out_offsets, offsets.data(), sizeof(int32_t) * (m + 1));
  if (!lits.empty())
    memcpy(*out_lits, lits.data(), sizeof(int32_t) * (size_t)lits.size());

  return 1;
}

// Solve (possibly to completion) and return both the current model (if SAT)
// and the learned clauses collected during the run.
//
// Return value follows CaDiCaL convention:
//   10 = SAT, 20 = UNSAT, 0 = UNKNOWN
//
// Model is returned in `out_model` as an array of length `nvars`.
// For variable v in 1..nvars:
//   out_model[v-1] =  v  if v is assigned true
//                  = -v  if v is assigned false
//                  =  0  if unassigned/unknown
//
// Caller must free out_lits, out_offsets, and out_model using free().
int cadical_solve_and_mine(
    // CNF input in flattened form: in_offsets length = nclauses+1
    const int32_t* in_lits,
    const int32_t* in_offsets,
    int32_t nclauses,
    int32_t nvars,
    // limits
    int32_t conflict_limit,
    int32_t max_len,
    int32_t max_lbd,
    // outputs: learned clauses (flattened)
    int32_t** out_lits,
    int32_t** out_offsets,
    int32_t* out_nclauses,
    int32_t* out_nlits,
    // outputs: model (length nvars)
    int32_t** out_model
) {
  Solver s;

  s.reserve(nvars);

  // feed CNF
  for (int32_t i = 0; i < nclauses; ++i) {
    int32_t a = in_offsets[i];
    int32_t b = in_offsets[i + 1];
    for (int32_t k = a; k < b; ++k) s.add((int)in_lits[k]);
    s.add(0);
  }

  (void)max_lbd; // LBD filtering not supported by this Learner interface
  Collector col(max_len);
  s.connect_learner(&col);

  // Conflict limits are per-solve in CaDiCaL.
  if (conflict_limit > 0) s.limit("conflicts", conflict_limit);

  int res = s.solve();

  // export model
  *out_model = (int32_t*)malloc(sizeof(int32_t) * (size_t)nvars);
  if (!*out_model) return 0;

  if (res == 10) {
    for (int32_t v = 1; v <= nvars; ++v) {
      int val = s.val((int)v);
      if (val > 0) (*out_model)[v - 1] = v;
      else if (val < 0) (*out_model)[v - 1] = -v;
      else (*out_model)[v - 1] = 0;
    }
  } else {
    // UNSAT or UNKNOWN: no model
    for (int32_t v = 1; v <= nvars; ++v) (*out_model)[v - 1] = 0;
  }

  // flatten learned clauses
  int32_t m = (int32_t)col.clauses.size();
  std::vector<int32_t> offsets(m + 1, 0);
  int64_t total = 0;
  for (int32_t i = 0; i < m; ++i) {
    offsets[i] = (int32_t)total;
    total += (int32_t)col.clauses[i].size();
  }
  offsets[m] = (int32_t)total;

  std::vector<int32_t> lits;
  lits.reserve((size_t)total);
  for (auto &c : col.clauses) lits.insert(lits.end(), c.begin(), c.end());

  *out_nclauses = m;
  *out_nlits = (int32_t)lits.size();

  *out_offsets = (int32_t*)malloc(sizeof(int32_t) * (m + 1));
  *out_lits    = (int32_t*)malloc(sizeof(int32_t) * (size_t)lits.size());
  if (!*out_offsets || (!*out_lits && !lits.empty())) return 0;

  memcpy(*out_offsets, offsets.data(), sizeof(int32_t) * (m + 1));
  if (!lits.empty())
    memcpy(*out_lits, lits.data(), sizeof(int32_t) * (size_t)lits.size());

  return res;
}

} // extern "C"

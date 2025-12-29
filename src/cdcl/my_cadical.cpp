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

  // Disable factor/factorcheck to avoid "undeclared variable" errors
  s.set("factor", 0);
  s.set("factorcheck", 0);

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

  // Disable factor/factorcheck to avoid "undeclared variable" errors
  s.set("factor", 0);
  s.set("factorcheck", 0);

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

// =============================================================================
// Solve with statistics for path analysis
// =============================================================================

// Solve and return statistics about the solving process
// This is useful for comparing CDCL behavior with tensor network approaches
//
// Returns:
//   10 = SAT, 20 = UNSAT, 0 = UNKNOWN
//
// out_decisions: number of decisions made
// out_conflicts: number of conflicts encountered
// out_propagations: number of propagations
//
// Caller must free out_model using free().
int cadical_solve_with_stats(
    // CNF input in flattened form
    const int32_t* in_lits,
    const int32_t* in_offsets,
    int32_t nclauses,
    int32_t nvars,
    // outputs: statistics
    int64_t* out_decisions,
    int64_t* out_conflicts,
    int64_t* out_propagations,
    int64_t* out_restarts,
    // output: model (length nvars, caller must free)
    int32_t** out_model
) {
  Solver s;

  // Disable factor/factorcheck
  s.set("factor", 0);
  s.set("factorcheck", 0);

  // feed CNF
  for (int32_t i = 0; i < nclauses; ++i) {
    int32_t a = in_offsets[i];
    int32_t b = in_offsets[i + 1];
    for (int32_t k = a; k < b; ++k) s.add((int)in_lits[k]);
    s.add(0);
  }

  int res = s.solve();

  // Get statistics using get_statistic_value()
  *out_decisions = s.get_statistic_value("decisions");
  *out_conflicts = s.get_statistic_value("conflicts");
  *out_propagations = s.get_statistic_value("propagations");
  *out_restarts = s.get_statistic_value("restarts");

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
    for (int32_t v = 1; v <= nvars; ++v) (*out_model)[v - 1] = 0;
  }

  return res;
}

// =============================================================================
// Decision Tracker - ExternalPropagator to capture VSIDS decisions
// =============================================================================

class DecisionTracker : public ExternalPropagator {
public:
  std::vector<int32_t> decision_vars;  // Variables chosen at each decision level
  std::vector<int32_t> current_trail;  // Current assignment trail
  int current_level = 0;
  
  // Track when a new decision level starts - the next assignment is a decision
  bool expecting_decision = false;
  
  void notify_assignment(const std::vector<int>& lits) override {
    for (int lit : lits) {
      if (expecting_decision) {
        // This is a decision variable (first assignment after new level)
        decision_vars.push_back(abs(lit));
        expecting_decision = false;
      }
      current_trail.push_back(lit);
    }
  }
  
  void notify_new_decision_level() override {
    current_level++;
    expecting_decision = true;  // Next assignment will be a decision
  }
  
  void notify_backtrack(size_t new_level) override {
    current_level = (int)new_level;
    // Note: we don't remove from decision_vars, we keep the full history
  }
  
  bool cb_check_found_model(const std::vector<int>& model) override {
    (void)model;
    return true;  // Accept any model
  }
  
  bool cb_has_external_clause(bool& is_forgettable) override {
    (void)is_forgettable;
    return false;  // No external clauses
  }
  
  int cb_add_external_clause_lit() override {
    return 0;
  }
};

// Solve and return the decision variable sequence (for VSIDS vs MinGamma comparison)
// Returns:
//   10 = SAT, 20 = UNSAT, 0 = UNKNOWN
//
// out_decision_vars: array of decision variables (absolute var IDs, in order)
// out_n_decisions: number of unique decisions made (including backtracks)
//
// Caller must free out_decision_vars and out_model using free().
int cadical_solve_with_decisions(
    // CNF input in flattened form
    const int32_t* in_lits,
    const int32_t* in_offsets,
    int32_t nclauses,
    int32_t nvars,
    // outputs: decision sequence
    int32_t** out_decision_vars,
    int32_t* out_n_decisions,
    // output: statistics
    int64_t* out_conflicts,
    // output: model (length nvars, caller must free)
    int32_t** out_model
) {
  Solver s;

  // Disable factor/factorcheck
  s.set("factor", 0);
  s.set("factorcheck", 0);

  // feed CNF
  for (int32_t i = 0; i < nclauses; ++i) {
    int32_t a = in_offsets[i];
    int32_t b = in_offsets[i + 1];
    for (int32_t k = a; k < b; ++k) s.add((int)in_lits[k]);
    s.add(0);
  }

  // Connect decision tracker FIRST
  DecisionTracker tracker;
  s.connect_external_propagator(&tracker);
  
  // Now we can observe all variables
  for (int32_t v = 1; v <= nvars; ++v) {
    s.add_observed_var(v);
  }

  int res = s.solve();

  // Export decision sequence
  int32_t nd = (int32_t)tracker.decision_vars.size();
  *out_n_decisions = nd;
  
  *out_decision_vars = (int32_t*)malloc(sizeof(int32_t) * (size_t)(nd > 0 ? nd : 1));
  if (!*out_decision_vars) return 0;
  
  if (nd > 0) {
    memcpy(*out_decision_vars, tracker.decision_vars.data(), sizeof(int32_t) * (size_t)nd);
  }

  // Get conflict count
  *out_conflicts = s.get_statistic_value("conflicts");

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
    for (int32_t v = 1; v <= nvars; ++v) (*out_model)[v - 1] = 0;
  }
  
  // Disconnect propagator
  s.disconnect_external_propagator();

  return res;
}

} // extern "C"




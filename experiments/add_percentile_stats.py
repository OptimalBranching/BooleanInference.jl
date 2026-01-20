#!/usr/bin/env python3
"""
Extract P95/P99 statistics from experiment result txt files and add them to CSV files.
"""

import re
import csv
from typing import Dict, Tuple, Optional

def extract_percentile_stats(txt_file: str) -> Dict[Tuple[str, str], Dict[str, float]]:
    """
    Extract P95/P99 statistics from a txt file.

    Returns a dictionary mapping (instance, solver) -> {stat_name: value}
    """
    stats = {}

    with open(txt_file, 'r') as f:
        content = f.read()

    # Pattern to match instance lines like "[1/10] Instance: 26x26_3147481895503969"
    instance_pattern = r'\[\d+/\d+\] Instance: (\S+)'

    # Pattern to match the solving cubes line with P95/P99 stats
    stats_pattern = (
        r'Solving cubes\.\.\. done\. wall_time=[\d.]+s \(serial=[\d.]+s\), '
        r'avg_dec=[\d.]+, '
        r'P95\(dec\)=([\d.]+), P99\(dec\)=([\d.]+), '
        r'P95\(conf\)=([\d.]+), P99\(conf\)=([\d.]+), '
        r'P95\(T\)=([\d.]+), P99\(T\)=([\d.]+)'
    )

    # Split content into sections by instance
    sections = re.split(instance_pattern, content)

    # Process each instance (skip first empty section)
    for i in range(1, len(sections), 2):
        instance_name = sections[i]
        instance_content = sections[i + 1]

        # Find all stats lines (both BI-CnC and march_cu-CnC)
        solver_sections = re.split(r'- (BI-CnC|march_cu-CnC):', instance_content)

        for j in range(1, len(solver_sections), 2):
            solver = solver_sections[j]
            solver_content = solver_sections[j + 1]

            # Extract P95/P99 stats
            match = re.search(stats_pattern, solver_content)
            if match:
                p95_dec, p99_dec, p95_conf, p99_conf, p95_t, p99_t = map(float, match.groups())

                key = (instance_name, solver)
                stats[key] = {
                    'p95_decisions': p95_dec,
                    'p99_decisions': p99_dec,
                    'p95_conflicts': p95_conf,
                    'p99_conflicts': p99_conf,
                    'p95_time': p95_t,
                    'p99_time': p99_t
                }

    return stats


def update_csv_with_stats(csv_file: str, stats: Dict[Tuple[str, str], Dict[str, float]]):
    """
    Update a CSV file by adding P95/P99 columns.
    """
    # Read the CSV file
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        fieldnames = reader.fieldnames

    # Add new columns to fieldnames if not already present
    new_columns = ['p95_decisions', 'p99_decisions', 'p95_conflicts', 'p99_conflicts', 'p95_time', 'p99_time']
    for col in new_columns:
        if col not in fieldnames:
            fieldnames.append(col)

    # Update each row with the stats
    for row in rows:
        instance = row['instance']
        solver = row['solver']
        key = (instance, solver)

        if key in stats:
            for stat_name, stat_value in stats[key].items():
                row[stat_name] = stat_value
        else:
            # If no stats found, set to empty string
            for stat_name in new_columns:
                if stat_name not in row or not row[stat_name]:
                    row[stat_name] = ''

    # Write the updated CSV
    with open(csv_file, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Updated {csv_file} with {len(stats)} entries")


def main():
    """Main function to process both cnc26 and cnc28 files."""

    # Process cnc26
    print("Processing cnc26...")
    txt_file_26 = '/Users/xiweipan/Codes/BooleanInference/experiments/results/cnc26.txt'
    csv_file_26 = '/Users/xiweipan/Codes/BooleanInference/experiments/results/cnc26.csv'

    stats_26 = extract_percentile_stats(txt_file_26)
    print(f"Extracted {len(stats_26)} entries from {txt_file_26}")
    update_csv_with_stats(csv_file_26, stats_26)

    # Process cnc28
    print("\nProcessing cnc28...")
    txt_file_28 = '/Users/xiweipan/Codes/BooleanInference/experiments/results/cnc28.txt'
    csv_file_28 = '/Users/xiweipan/Codes/BooleanInference/experiments/results/cnc28.csv'

    stats_28 = extract_percentile_stats(txt_file_28)
    print(f"Extracted {len(stats_28)} entries from {txt_file_28}")
    update_csv_with_stats(csv_file_28, stats_28)

    print("\nDone!")


if __name__ == '__main__':
    main()

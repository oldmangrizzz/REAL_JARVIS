# Benchmark Notes

The current benchmark signal behind this kit is straightforward:
- combined ITP + modeled prompt caching produced about 62.56% mean total token reduction across tested multi-swarm scenarios
- the savings came from additive effects, not overlapping accounting tricks

This makes the pattern easy to explain to reviewers and practical for recurring grouped agent workloads.

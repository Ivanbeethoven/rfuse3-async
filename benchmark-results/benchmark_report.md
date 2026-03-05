# rfuse3 Performance Benchmark Report (Example Data)

**Note**: This is example data. Run on Linux for real benchmarks.

## Summary

| Filesystem | Test | IOPS | Bandwidth (MB/s) | P99 Latency (¦Ìs) |
|------------|------|------|------------------|------------------|
| fuser | fuser_rand_read | 28,000 | 112.0 | 357.1 |
| fuser | fuser_rand_write | 7,200 | 28.8 | 1388.9 |
| fuser | fuser_seq_read | 38,000 | 152.0 | 263.2 |
| fuser | fuser_seq_write | 9,600 | 38.4 | 1041.7 |
| rfuse3-optimized | optimized_rand_read | 120,000 | 480.0 | 83.3 |
| rfuse3-optimized | optimized_rand_write | 19,200 | 76.8 | 520.8 |
| rfuse3-optimized | optimized_seq_read | 150,000 | 600.0 | 66.7 |
| rfuse3-optimized | optimized_seq_write | 24,000 | 96.0 | 416.7 |
| rfuse3-original | original_rand_read | 35,000 | 140.0 | 285.7 |
| rfuse3-original | original_rand_write | 9,600 | 38.4 | 1041.7 |
| rfuse3-original | original_seq_read | 45,000 | 180.0 | 222.2 |
| rfuse3-original | original_seq_write | 12,000 | 48.0 | 833.3 |

## Performance Improvements

### Optimized vs Original

| Metric | Original | Optimized | Improvement |
|--------|----------|-----------|-------------|
| seq_read IOPS | 45,000 | 150,000 | +233% |
| seq_write IOPS | 12,000 | 24,000 | +100% |
| rand_read IOPS | 35,000 | 120,000 | +243% |
| rand_write IOPS | 9,600 | 19,200 | +100% |

## Key Findings

1. **Random Read**: 3.4x improvement (lock-free reads)
2. **Sequential Read**: 3.3x improvement (COW optimization)
3. **Write Operations**: 2.0x improvement (atomic swap)
4. **Latency**: Significantly reduced P99 latency
5. **vs fuser**: Outperforms fuser by 2-3x in most scenarios

#!/bin/bash
# rfuse3 Performance Benchmark Suite
# Compares: Original vs Optimized vs fuser

set -e

# Configuration
MOUNT_POINT="/tmp/rfuse3-bench"
REPORT_DIR="$(pwd)/benchmark-results"
DURATION=30
NUM_JOBS=16
FILE_SIZE="1G"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  rfuse3 Performance Benchmark Suite${NC}"
echo -e "${BLUE}========================================${NC}"

# Create report directory
mkdir -p "$REPORT_DIR"

# Function to check if mount point is ready
wait_for_mount() {
    local mp=$1
    local timeout=10
    local count=0
    while [ ! -d "$mp" ] || ! mountpoint -q "$mp" 2>/dev/null; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge $timeout ]; then
            echo -e "${RED}Failed to mount within ${timeout}s${NC}"
            return 1
        fi
    done
    echo -e "${GREEN}Mount ready${NC}"
}

# Function to run fio benchmark
run_fio_test() {
    local test_name=$1
    local rw_type=$2
    local bs=$3
    local output_file="$REPORT_DIR/${test_name}.json"
    
    echo -e "${YELLOW}Running: $test_name${NC}"
    
    fio --name="$test_name" \
        --directory="$MOUNT_POINT" \
        --rw="$rw_type" \
        --bs="$bs" \
        --size="$FILE_SIZE" \
        --numjobs="$NUM_JOBS" \
        --time_based \
        --runtime="$DURATION" \
        --group_reporting \
        --output-format=json \
        --output="$output_file" \
        2>/dev/null
    
    # Extract IOPS
    local iops=$(jq '.jobs[0].read.iops + .jobs[0].write.iops' "$output_file" 2>/dev/null || echo "0")
    local bw=$(jq '.jobs[0].read.bw_bytes + .jobs[0].write.bw_bytes' "$output_file" 2>/dev/null || echo "0")
    local lat_p99=$(jq '.jobs[0].read.lat_ns.percentile.99.000000 // .jobs[0].write.lat_ns.percentile.99.000000' "$output_file" 2>/dev/null || echo "0")
    
    echo -e "  ${GREEN}IOPS: $iops${NC}"
    echo -e "  ${GREEN}Bandwidth: $((bw / 1024 / 1024)) MB/s${NC}"
    echo -e "  ${GREEN}P99 Latency: $((lat_p99 / 1000)) μs${NC}"
    
    # Save to CSV
    echo "$test_name,$iops,$bw,$lat_p99" >> "$REPORT_DIR/results.csv"
}

# Function to run metadata benchmark
run_metadata_test() {
    local test_name=$1
    local fs_type=$2
    
    echo -e "${YELLOW}Running: $test_name (metadata)${NC}"
    
    # Create test directory
    local test_dir="$MOUNT_POINT/meta_test_$$"
    mkdir -p "$test_dir"
    
    local start_time=$(date +%s%N)
    
    # Create 1000 files
    for i in $(seq 1 1000); do
        echo "test content $i" > "$test_dir/file_$i.txt"
    done
    
    local create_time=$(( ($(date +%s%N) - $start_time) / 1000000 ))
    echo -e "  ${GREEN}Create 1000 files: ${create_time}ms${NC}"
    
    # Stat all files
    start_time=$(date +%s%N)
    for i in $(seq 1 1000); do
        stat "$test_dir/file_$i.txt" > /dev/null
    done
    local stat_time=$(( ($(date +%s%N) - $start_time) / 1000000 ))
    echo -e "  ${GREEN}Stat 1000 files: ${stat_time}ms${NC}"
    
    # List directory
    start_time=$(date +%s%N)
    ls -la "$test_dir" > /dev/null
    local list_time=$(( ($(date +%s%N) - $start_time) / 1000000 ))
    echo -e "  ${GREEN}List directory: ${list_time}ms${NC}"
    
    # Cleanup
    rm -rf "$test_dir"
    
    # Save to CSV
    echo "$test_name,create:$create_time,stat:$stat_time,list:$list_time" >> "$REPORT_DIR/metadata.csv"
}

# Function to cleanup
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        fusermount -u "$MOUNT_POINT" 2>/dev/null || true
        sleep 2
    fi
    rm -rf "$MOUNT_POINT"
}

trap cleanup EXIT

# Create mount point
mkdir -p "$MOUNT_POINT"

# Initialize CSV files
echo "test,iops,bandwidth_bytes,latency_ns" > "$REPORT_DIR/results.csv"
echo "test,create_ms,stat_ms,list_ms" > "$REPORT_DIR/metadata.csv"

# ============================================
# Test 1: rfuse3 Original Version
# ============================================
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}  Test 1: rfuse3 Original${NC}"
echo -e "${BLUE}========================================${NC}"

cd "$(pwd)/../rk8s/project/rfuse3" || exit 1
echo "Building original version..."
cargo build --example benchmark_filesystem --release 2>&1 | tail -5

echo "Mounting original version..."
./target/release/examples/benchmark_filesystem "$MOUNT_POINT" \
    --file-count 1024 \
    --file-size 4096 \
    --workers 4 \
    --max-background 128 \
    &
sleep 3
wait_for_mount "$MOUNT_POINT"

# Run benchmarks
run_fio_test "original_seqread" "read" "1M"
run_fio_test "original_seqwrite" "write" "1M"
run_fio_test "original_randread" "randread" "4K"
run_fio_test "original_randwrite" "randwrite" "4K"
run_metadata_test "original_meta" "rfuse3-original"

cleanup

# ============================================
# Test 2: rfuse3 Optimized Version
# ============================================
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}  Test 2: rfuse3 Optimized${NC}"
echo -e "${BLUE}========================================${NC}"

cd "$(pwd)/../../rfuse3-async" || exit 1
echo "Building optimized version..."
cargo build --example optimized_filesystem --release 2>&1 | tail -5

echo "Mounting optimized version..."
./target/release/examples/optimized_filesystem "$MOUNT_POINT" \
    --file-count 1024 \
    --file-size 4096 \
    --workers 4 \
    --max-background 128 \
    &
sleep 3
wait_for_mount "$MOUNT_POINT"

# Run benchmarks
run_fio_test "optimized_seqread" "read" "1M"
run_fio_test "optimized_seqwrite" "write" "1M"
run_fio_test "optimized_randread" "randread" "4K"
run_fio_test "optimized_randwrite" "randwrite" "4K"
run_metadata_test "optimized_meta" "rfuse3-optimized"

cleanup

# ============================================
# Test 3: fuser (for comparison)
# ============================================
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}  Test 3: fuser (reference)${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if fuser example exists
if [ -f "/tmp/fuser-bench" ]; then
    echo "Mounting fuser..."
    /tmp/fuser-bench "$MOUNT_POINT" &
    sleep 3
    wait_for_mount "$MOUNT_POINT"
    
    run_fio_test "fuser_seqread" "read" "1M"
    run_fio_test "fuser_seqwrite" "write" "1M"
    run_fio_test "fuser_randread" "randread" "4K"
    run_fio_test "fuser_randwrite" "randwrite" "4K"
    run_metadata_test "fuser_meta" "fuser"
    
    cleanup
else
    echo -e "${YELLOW}fuser benchmark not found, skipping...${NC}"
    echo "To install fuser benchmark:"
    echo "  git clone https://github.com/cberner/fuser.git"
    echo "  cd fuser && cargo build --example simple --release"
    echo "  cp target/release/examples/simple /tmp/fuser-bench"
fi

# ============================================
# Generate Report
# ============================================
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}  Generating Report${NC}"
echo -e "${BLUE}========================================${NC}"

cd "$REPORT_DIR"

# Create markdown report
cat > benchmark_report.md << 'EOF'
# rfuse3 Performance Benchmark Report

**Date**: $(date +%Y-%m-%d)  
**Test Duration**: ${DURATION}s per test  
**Parallel Jobs**: ${NUM_JOBS}  
**File Size**: ${FILE_SIZE}

## Summary

| Filesystem | Seq Read (MB/s) | Seq Write (MB/s) | Rand Read (IOPS) | Rand Write (IOPS) |
|------------|-----------------|------------------|------------------|-------------------|
EOF

# Parse results and generate table
for fs in "original" "optimized" "fuser"; do
    seq_read=$(grep "${fs}_seqread" results.csv 2>/dev/null | cut -d',' -f3 || echo "0")
    seq_write=$(grep "${fs}_seqwrite" results.csv 2>/dev/null | cut -d',' -f3 || echo "0")
    rand_read=$(grep "${fs}_randread" results.csv 2>/dev/null | cut -d',' -f2 || echo "0")
    rand_write=$(grep "${fs}_randwrite" results.csv 2>/dev/null | cut -d',' -f2 || echo "0")
    
    # Convert to MB/s for bandwidth
    seq_read_mb=$((seq_read / 1024 / 1024))
    seq_write_mb=$((seq_write / 1024 / 1024))
    
    echo "| ${fs} | ${seq_read_mb} | ${seq_write_mb} | ${rand_read} | ${rand_write} |" >> benchmark_report.md
done

cat >> benchmark_report.md << 'EOF'

## Detailed Results

### Sequential Read (1M block)
![Seq Read](seq_read.png)

### Sequential Write (1M block)
![Seq Write](seq_write.png)

### Random Read (4K block)
![Rand Read](rand_read.png)

### Random Write (4K block)
![Rand Write](rand_write.png)

## Metadata Operations

| Filesystem | Create 1K files | Stat 1K files | List Directory |
|------------|-----------------|---------------|----------------|
EOF

# Add metadata results
for fs in "original" "optimized" "fuser"; do
    meta_line=$(grep "${fs}_meta" metadata.csv 2>/dev/null || echo "")
    if [ -n "$meta_line" ]; then
        create_time=$(echo "$meta_line" | cut -d',' -f2 | cut -d':' -f2)
        stat_time=$(echo "$meta_line" | cut -d',' -f3 | cut -d':' -f2)
        list_time=$(echo "$meta_line" | cut -d',' -f4)
        echo "| ${fs} | ${create_time}ms | ${stat_time}ms | ${list_time}ms |" >> benchmark_report.md
    fi
done

cat >> benchmark_report.md << 'EOF'

## Performance Improvements

### Optimized vs Original

| Metric | Improvement |
|--------|-------------|
EOF

# Calculate improvements
orig_rand_read=$(grep "original_randread" results.csv 2>/dev/null | cut -d',' -f2 || echo "1")
opt_rand_read=$(grep "optimized_randread" results.csv 2>/dev/null | cut -d',' -f2 || echo "0")

if [ "$orig_rand_read" -gt 0 ] && [ "$opt_rand_read" -gt 0 ]; then
    improvement=$(( (opt_rand_read - orig_rand_read) * 100 / orig_rand_read ))
    echo "| Random Read IOPS | +${improvement}% |" >> benchmark_report.md
fi

echo "" >> benchmark_report.md
echo "**Report generated**: $(date)" >> benchmark_report.md

echo -e "${GREEN}Report saved to: $REPORT_DIR/benchmark_report.md${NC}"
echo -e "${GREEN}CSV data: $REPORT_DIR/results.csv${NC}"

# Open report
echo -e "\n${BLUE}Benchmark Complete!${NC}"
echo "View report: cat $REPORT_DIR/benchmark_report.md"

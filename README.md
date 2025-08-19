## 📊 Overview
ktop is a powerful command-line tool for monitoring Kubernetes node resource allocation and usage. It provides a comprehensive view of CPU and memory requests, limits, actual usage, and capacity across all nodes in your cluster, similar to htop but for Kubernetes nodes.

## ✨ Features
Real-time Resource Monitoring: View CPU and memory requests, limits, usage, and capacity
Smart Memory Corruption Handling: Automatically detects and fixes Kubernetes memory reporting bugs
Flexible Sorting: Sort by any column (CPU/Memory requests, limits, usage, percentage, capacity)
Parallel Processing: Fast data collection with configurable parallel queries
Multiple Output Formats: Table (default), CSV, JSON
Watch Mode: Auto-refresh display at specified intervals
Color-Coded Alerts: Visual indicators for resource usage levels
- 🟢 Green: 0-59% (Normal)
- 🟡 Yellow: 60-79% (Warning)
- 🔴 Red: 80%+ (Critical)

Node Filtering: Include or exclude control-plane nodes
Resource Totals: Summary row showing cluster-wide resource allocation

## 📋 Requirements
- Kubernetes cluster (v1.19+)
- kubectl configured with cluster access
- metrics-server installed in the cluster
- jq for JSON parsing
- bc for calculations
- bash 4.0+

## 🚀 Installation
````bash
    # Download the script
    curl -Lo ~/bin/ktop https://raw.githubusercontent.com/sbahmani/ktop/refs/heads/main/ktop.sh
    
    # Make it executable
    chmod +x ~/bin/ktop
    
    # Add to PATH (if not already)
    echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    
    # Verify installation
    ktop --help
````
### Install metrics-server (if not installed)
````bash
kubectl apply -f https://github.com/kubernetes-metrics/metrics-server/releases/latest/download/components.yaml
````

## 📖 Usage
````bash
# Display all worker nodes with default settings
ktop

# Use 12 parallel queries for faster execution
ktop -P 12

# Include control-plane nodes
ktop --all

# Sort by CPU usage (highest first)
ktop -S cpu-use

# Sort by memory percentage
ktop -S mem-pct

# Watch mode - refresh every 5 seconds
ktop -w 5
````
### Command-Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `-h, --help` | Show help message | `ktop -h` |
| `-P <num>` | Number of parallel kubectl queries (default: 4) | `ktop -P 8` |
| `-a, --all` | Include control-plane nodes | `ktop --all` |
| `-n, --no-color` | Disable color output | `ktop --no-color` |
| `-s, --no-sum` | Don't show summary totals | `ktop --no-sum` |
| `-w, --watch <sec>` | Auto-refresh every N seconds | `ktop -w 10` |
| `-o, --output <fmt>` | Output format: table, csv, json | `ktop -o csv` |
| `-S, --sort <field>` | Sort by field | `ktop -S cpu-pct` |
| `-r, --reverse` | Reverse sort order (ascending) | `ktop -S name -r` |

### Sort Fields

| Field | Description |
|-------|-------------|
| `name` | Node name (alphabetical) |
| `cpu-req` | CPU requests (default) |
| `cpu-lim` | CPU limits |
| `cpu-use` | CPU actual usage |
| `cpu-pct` | CPU usage percentage |
| `cpu-cap` | CPU capacity |
| `mem-req` | Memory requests |
| `mem-lim` | Memory limits |
| `mem-use` | Memory actual usage |
| `mem-pct` | Memory usage percentage |
| `mem-cap` | Memory capacity |

## 📊 Output Example

```
WORKER_NODE        CPU_REQ  CPU_LIM  CPU_USE  CPU_%  CPU_CAP  | MEM_REQ  MEM_LIM  MEM_USE  MEM_%  MEM_CAP
========================================================================================================
worker07           78573m   184732m  44905m   40%    111.5    | 252.8Gi  301.6Gi  137.2Gi  27%    494.5Gi
worker09           77925m   168720m  35093m   31%    111.5    | 146.0Gi  187.8Gi  126.8Gi  25%    494.5Gi
worker08           77075m   157220m  43008m   38%    111.5    | 141.0Gi  176.0Gi  131.4Gi  26%    494.5Gi
worker-gpu-02      72161m   208884m  1206m    0%     127.5    | 489.2Gi  1047.4Gi 446.5Gi  44%    993.6Gi
...
========================================================================================================
TOTAL (58)         3272.9   7225.0   1552.4   -      5018.8   | 8117.2Gi 12621.0Gi 7869.1Gi -     22998.8Gi
```

### Output Columns

- **WORKER_NODE**: Node name
- **CPU_REQ**: CPU requests allocated to pods
- **CPU_LIM**: CPU limits allocated to pods
- **CPU_USE**: Actual CPU usage
- **CPU_%**: CPU usage percentage of node capacity
- **CPU_CAP**: Total CPU capacity (cores)
- **MEM_REQ**: Memory requests allocated to pods (Gi)
- **MEM_LIM**: Memory limits allocated to pods (Gi)
- **MEM_USE**: Actual memory usage (Gi)
- **MEM_%**: Memory usage percentage of node capacity
- **MEM_CAP**: Total memory capacity (Gi)


### Export and Analysis

```bash
# Export to CSV for spreadsheet analysis
ktop -o csv > node_resources_$(date +%Y%m%d).csv

# Export to JSON for programmatic processing
ktop -o json | jq '.nodes[] | select(.cpu_pct > 80)'

# Create a resource utilization report
ktop --all -o csv | awk -F',' 'NR>1 {print $1","$4","$9}'
```

## 🐛 Troubleshooting

### Common Issues

1. **"metrics-server is not installed or not working"**
   ```bash
   # Install metrics-server
   kubectl apply -f https://github.com/kubernetes-metrics/metrics-server/releases/latest/download/components.yaml
   
   # Verify metrics-server is running
   kubectl get deployment metrics-server -n kube-system
   ```

2. **Memory values showing as 0Gi or incorrect**
   - The script automatically detects and fixes Kubernetes memory reporting bugs
   - For nodes showing corrupted values, the script calculates actual memory from pod specifications

3. **Slow performance**
   - Increase parallel queries: `ktop -P 16`
   - Reduce scope: exclude control-plane nodes (default behavior)

4. **No color in output**
   - Check terminal support: `echo $TERM`
   - Force color: `TERM=xterm-256color ktop`

## 🔧 Configuration

### Environment Variables

```bash
# Set default parallel queries
export KTOP_PARALLEL=12

# Set default output format
export KTOP_FORMAT=table

# Disable color by default
export KTOP_NO_COLOR=true
```


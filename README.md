📊 Overview
ktop is a powerful command-line tool for monitoring Kubernetes node resource allocation and usage. It provides a comprehensive view of CPU and memory requests, limits, actual usage, and capacity across all nodes in your cluster, similar to htop but for Kubernetes nodes.

✨ Features
Real-time Resource Monitoring: View CPU and memory requests, limits, usage, and capacity
Smart Memory Corruption Handling: Automatically detects and fixes Kubernetes memory reporting bugs
Flexible Sorting: Sort by any column (CPU/Memory requests, limits, usage, percentage, capacity)
Parallel Processing: Fast data collection with configurable parallel queries
Multiple Output Formats: Table (default), CSV, JSON
Watch Mode: Auto-refresh display at specified intervals
Color-Coded Alerts: Visual indicators for resource usage levels
🟢 Green: 0-59% (Normal)
🟡 Yellow: 60-79% (Warning)
🔴 Red: 80%+ (Critical)
Node Filtering: Include or exclude control-plane nodes
Resource Totals: Summary row showing cluster-wide resource allocation

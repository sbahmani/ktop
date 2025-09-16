#!/bin/bash

# ktop - Kubernetes Node Resource Monitor
# Description: Display worker node resource allocation and usage with sorting options

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

# Default settings
PARALLEL=4
OUTPUT_FORMAT="table"
SHOW_ALL=false
NO_COLOR=false
NO_SUM=false
WATCH_INTERVAL=0
SORT_BY="cpu-req"  # Default sort by CPU requests
SORT_ORDER="desc"  # Default descending order

# Help function
show_help() {
    echo -e "${BOLD}ktop - Kubernetes Worker Node Resource Monitor${NC}"
    echo ""
    echo -e "${BOLD}USAGE:${NC}"
    echo "    ktop [OPTIONS]"
    echo ""
    echo -e "${BOLD}DESCRIPTION:${NC}"
    echo "    Display Kubernetes worker nodes' CPU and memory allocation, usage, and capacity."
    echo "    Shows resource requests, limits, actual usage, percentages, and total capacity."
    echo ""
    echo -e "${BOLD}OPTIONS:${NC}"
    echo "    -h, --help          Show this help message"
    echo "    -P <num>            Number of parallel kubectl queries (default: 4)"
    echo "    -a, --all           Include control-plane nodes"
    echo "    -n, --no-color      Disable color output"
    echo "    -s, --no-sum        Don't show summary totals"
    echo "    -w, --watch <sec>   Auto-refresh every N seconds"
    echo "    -o, --output <fmt>  Output format: table (default), csv, json"
    echo "    -S, --sort <field>  Sort by field (default: cpu-req)"
    echo "    -r, --reverse       Reverse sort order (ascending)"
    echo ""
    echo -e "${BOLD}SORT FIELDS:${NC}"
    echo "    name        Node name (alphabetical)"
    echo "    cpu-req     CPU requests (default)"
    echo "    cpu-lim     CPU limits"
    echo "    cpu-use     CPU usage"
    echo "    cpu-pct     CPU usage percentage"
    echo "    cpu-cap     CPU capacity"
    echo "    mem-req     Memory requests"
    echo "    mem-lim     Memory limits"
    echo "    mem-use     Memory usage"
    echo "    mem-pct     Memory usage percentage"
    echo "    mem-cap     Memory capacity"
    echo ""
    echo -e "${BOLD}EXAMPLES:${NC}"
    echo "    ktop                        # Default: sort by CPU requests"
    echo "    ktop -S cpu-use             # Sort by CPU usage"
    echo "    ktop -S mem-pct             # Sort by memory usage percentage"
    echo "    ktop -S name -r             # Sort by name ascending"
    echo "    ktop --sort cpu-pct         # Sort by CPU percentage"
    echo "    ktop -S mem-use --all       # Sort by memory usage, include control-plane"
    echo "    ktop -S cpu-use -w 5        # Sort by CPU usage, refresh every 5s"
    echo "    ktop -P 12 -S cpu-pct       # Use 12 parallel queries, sort by CPU%"
    echo ""
    echo -e "${BOLD}OUTPUT COLUMNS:${NC}"
    echo "    WORKER_NODE    Node name"
    echo "    CPU_REQ        CPU requests allocated to pods"
    echo "    CPU_LIM        CPU limits allocated to pods"
    echo "    CPU_USE        Actual CPU usage"
    echo "    CPU_%          CPU usage percentage of node capacity"
    echo "    CPU_CAP        Total CPU capacity (cores)"
    echo "    MEM_REQ        Memory requests allocated to pods (Gi)"
    echo "    MEM_LIM        Memory limits allocated to pods (Gi)"
    echo "    MEM_USE        Actual memory usage (Gi)"
    echo "    MEM_%          Memory usage percentage of node capacity"
    echo "    MEM_CAP        Total memory capacity (Gi)"
    echo ""
    echo -e "${BOLD}COLOR CODING:${NC}"
    echo -e "    ${GREEN}Green${NC}   0-59%  - Normal usage"
    echo -e "    ${YELLOW}Yellow${NC}  60-79% - Medium usage"
    echo -e "    ${RED}Red${NC}     80%+   - High usage"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -P)
            if [[ ! "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: -P requires a numeric value"
                exit 1
            fi
            PARALLEL="$2"
            shift 2
            ;;
        -a|--all)
            SHOW_ALL=true
            shift
            ;;
        -n|--no-color)
            NO_COLOR=true
            RED=''; YELLOW=''; GREEN=''; BOLD=''; NC=''
            shift
            ;;
        -s|--no-sum)
            NO_SUM=true
            shift
            ;;
        -w|--watch)
            if [[ ! "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: -w requires a numeric value (seconds)"
                exit 1
            fi
            WATCH_INTERVAL="$2"
            shift 2
            ;;
        -o|--output)
            if [[ ! "$2" =~ ^(table|csv|json)$ ]]; then
                echo "Error: Output format must be: table, csv, or json"
                exit 1
            fi
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -S|--sort)
            if [[ ! "$2" =~ ^(name|cpu-req|cpu-lim|cpu-use|cpu-pct|cpu-cap|mem-req|mem-lim|mem-use|mem-pct|mem-cap)$ ]]; then
                echo "Error: Invalid sort field. Use 'ktop -h' to see valid options"
                exit 1
            fi
            SORT_BY="$2"
            shift 2
            ;;
        -r|--reverse)
            SORT_ORDER="asc"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use 'ktop -h' for help"
            exit 1
            ;;
    esac
done

# Check dependencies
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed or not in PATH"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo "Error: bc is not installed or not in PATH"
    exit 1
fi

# Check kubectl access
if ! kubectl get nodes &> /dev/null; then
    echo "Error: Cannot access Kubernetes cluster. Check your kubeconfig."
    exit 1
fi

# Check metrics-server
if ! kubectl top nodes &> /dev/null; then
    echo "Error: metrics-server is not installed or not working"
    echo "Install with: kubectl apply -f https://github.com/kubernetes-metrics/metrics-server/releases/latest/download/components.yaml"
    exit 1
fi

# Function to convert bytes/various formats to Gi
to_gi() {
    local value=$1
    
    # Handle corrupted memory values with 'm' suffix (Kubernetes bug)
    if [[ $value =~ ^[0-9]+m$ ]]; then
        local num_value=${value%m}
        # If it's a very large number (>10 digits), it's likely corrupted memory in bytes
        if [[ ${#num_value} -gt 10 ]]; then
            # Convert bytes to Gi
            local gi_value=$(echo "$num_value" | awk '{printf "%.1f", $1 / (1024*1024*1024)}')
            # Sanity check - if > 1000Gi, it's definitely corrupted
            if (( $(echo "$gi_value > 1000" | bc -l 2>/dev/null || echo 0) )); then
                echo "ERR"  # Mark as error to trigger pod calculation
                return
            fi
            echo "$gi_value"
            return
        else
            # Small number with 'm' - likely CPU millicores
            echo "0"
            return
        fi
    fi
    
    if [[ -z "$value" ]] || [[ "$value" == "0" ]]; then
        echo "0"
    elif [[ $value =~ ^[0-9]+$ ]]; then
        # Plain number - assume bytes and convert to Gi
        local gi_value=$(echo "$value" | awk '{printf "%.1f", $1 / (1024*1024*1024)}')
        # Sanity check
        if (( $(echo "$gi_value > 1000" | bc -l 2>/dev/null || echo 0) )); then
            echo "ERR"  # Mark as error
        else
            echo "$gi_value"
        fi
    elif [[ $value == *"Ti" ]]; then
        local num=${value%Ti}
        echo "$num" | awk '{printf "%.1f", $1 * 1024}'
    elif [[ $value == *"Gi" ]]; then
        echo "${value%Gi}"
    elif [[ $value == *"Mi" ]]; then
        local mi=${value%Mi}
        echo "$mi" | awk '{printf "%.1f", $1 / 1024}'
    elif [[ $value == *"Ki" ]]; then
        local ki=${value%Ki}
        echo "$ki" | awk '{printf "%.1f", $1 / (1024*1024)}'
    else
        echo "0"
    fi
}

# Function to convert Mi to Gi
mi_to_gi() {
    local mi=$1
    mi=${mi%Mi}  # Remove Mi suffix if present
    
    if [[ -z "$mi" ]] || [[ "$mi" == "0" ]]; then
        echo "0"
    else
        echo "$mi" | awk '{printf "%.1f", $1 / 1024}'
    fi
}

# Function to calculate memory from pods
calculate_mem_from_pods() {
    local node=$1
    
    kubectl get pods --all-namespaces --field-selector spec.nodeName=$node -o json 2>/dev/null | \
        jq -r '[.items[].spec.containers[].resources.requests.memory // "0"] | 
            map(
                if test("Ti$") then (. | rtrimstr("Ti") | tonumber * 1024)
                elif test("Gi$") then (. | rtrimstr("Gi") | tonumber)
                elif test("Mi$") then (. | rtrimstr("Mi") | tonumber / 1024)
                elif test("Ki$") then (. | rtrimstr("Ki") | tonumber / 1024 / 1024)
                elif test("^[0-9]+$") then (. | tonumber / 1024 / 1024 / 1024)
                else 0 end
            ) | add // 0' | \
        awk '{printf "%.1f", $1}'
}

# Process function
process_node() {
    local node=$1
    
    # Get node capacity from JSON
    local node_json=$(kubectl get node $node -o json 2>/dev/null)
    local cpu_capacity=$(echo "$node_json" | jq -r '.status.allocatable.cpu')
    local mem_capacity=$(echo "$node_json" | jq -r '.status.allocatable.memory')
    
    # Convert CPU capacity to cores
    local cpu_total
    if [[ $cpu_capacity == *"m" ]]; then
        cpu_total=$(echo "${cpu_capacity%m}" | awk '{printf "%.1f", $1 / 1000}')
    else
        cpu_total=$cpu_capacity
    fi
    
    # Convert memory capacity to Gi
    local mem_total_gi=$(to_gi "$mem_capacity")
    
    # Handle ERR values for memory capacity
    if [[ "$mem_total_gi" == "ERR" ]]; then
        # Try to get memory from status.capacity instead of allocatable
        mem_capacity=$(echo "$node_json" | jq -r '.status.capacity.memory')
        mem_total_gi=$(to_gi "$mem_capacity")
        
        # If still error, set to 0
        if [[ "$mem_total_gi" == "ERR" ]]; then
            mem_total_gi="0"
        fi
    fi
    
    # Get allocated resources from describe
    local describe=$(kubectl describe node $node 2>/dev/null)
    local allocated=$(echo "$describe" | grep -A 10 "Allocated resources:")
    
    # Extract CPU line
    local cpu_line=$(echo "$allocated" | grep "cpu" | head -1)
    local cpu_req=$(echo "$cpu_line" | awk '{print $2}')
    local cpu_lim=$(echo "$cpu_line" | awk '{print $4}')
    
    # Extract Memory line
    local mem_line=$(echo "$allocated" | grep "memory" | head -1)
    local mem_req_raw=$(echo "$mem_line" | awk '{print $2}')
    local mem_lim_raw=$(echo "$mem_line" | awk '{print $4}')
    
    # Default values if empty
    cpu_req=${cpu_req:-0m}
    cpu_lim=${cpu_lim:-0m}
    mem_req_raw=${mem_req_raw:-0}
    mem_lim_raw=${mem_lim_raw:-0}
    
    # Convert memory request to Gi
    local mem_req_gi=$(to_gi "$mem_req_raw")
    
    # If memory request conversion resulted in error or unreasonable value, calculate from pods
    if [[ "$mem_req_gi" == "ERR" ]] || [[ "$mem_req_raw" =~ ^[0-9]+m$ && ${#mem_req_raw} -gt 10 ]]; then
        mem_req_gi=$(calculate_mem_from_pods "$node")
    fi
    
    # Convert memory limit to Gi
    local mem_lim_gi=$(to_gi "$mem_lim_raw")
    if [[ "$mem_lim_gi" == "ERR" ]]; then
        # If limit is corrupted, use a reasonable default or calculate
        mem_lim_gi="0"
    fi
    
    # Get actual usage from kubectl top
    local top=$(kubectl top node $node --no-headers 2>/dev/null)
    local cpu_use=$(echo "$top" | awk '{print $2}')
    local cpu_use_pct=$(echo "$top" | awk '{print $3}' | tr -d '%')
    local mem_use_mi=$(echo "$top" | awk '{print $4}')
    local mem_use_pct=$(echo "$top" | awk '{print $5}' | tr -d '%')
    
    # Default values if empty
    cpu_use=${cpu_use:-0m}
    cpu_use_pct=${cpu_use_pct:-0}
    mem_use_mi=${mem_use_mi:-0Mi}
    mem_use_pct=${mem_use_pct:-0}
    
    # Convert memory usage to Gi
    local mem_use_gi=$(mi_to_gi "$mem_use_mi")
    
    # Prepare sort values
    local cpu_req_m=${cpu_req%m}
    local cpu_lim_m=${cpu_lim%m}
    local cpu_use_m=${cpu_use%m}
    [[ -z "$cpu_req_m" ]] && cpu_req_m=0
    [[ -z "$cpu_lim_m" ]] && cpu_lim_m=0
    [[ -z "$cpu_use_m" ]] && cpu_use_m=0
    
    # Ensure all memory values are numeric (not "ERR")
    [[ "$mem_req_gi" == "ERR" ]] && mem_req_gi="0"
    [[ "$mem_lim_gi" == "ERR" ]] && mem_lim_gi="0"
    [[ "$mem_use_gi" == "ERR" ]] && mem_use_gi="0"
    [[ "$mem_total_gi" == "ERR" ]] && mem_total_gi="0"
    
    # Determine sort value
    local sort_value
    case "$SORT_BY" in
        name)       sort_value="$node" ;;
        cpu-req)    sort_value=$(printf "%010d" $cpu_req_m) ;;
        cpu-lim)    sort_value=$(printf "%010d" $cpu_lim_m) ;;
        cpu-use)    sort_value=$(printf "%010d" $cpu_use_m) ;;
        cpu-pct)    sort_value=$(printf "%010d" ${cpu_use_pct:-0}) ;;
        cpu-cap)    sort_value=$(printf "%010.1f" ${cpu_total:-0}) ;;
        mem-req)    sort_value=$(printf "%010.1f" ${mem_req_gi:-0}) ;;
        mem-lim)    sort_value=$(printf "%010.1f" ${mem_lim_gi:-0}) ;;
        mem-use)    sort_value=$(printf "%010.1f" ${mem_use_gi:-0}) ;;
        mem-pct)    sort_value=$(printf "%010d" ${mem_use_pct:-0}) ;;
        mem-cap)    sort_value=$(printf "%010.1f" ${mem_total_gi:-0}) ;;
        *)          sort_value=$(printf "%010d" $cpu_req_m) ;;
    esac
    
    echo "$sort_value|$node|$cpu_req|$cpu_lim|$cpu_use|$cpu_use_pct|$cpu_total|$mem_req_gi|$mem_lim_gi|$mem_use_gi|$mem_use_pct|$mem_total_gi"
}

# Main display function
display_resources() {
    # Show sort info if not default
    if [[ "$SORT_BY" != "cpu-req" ]] || [[ "$SORT_ORDER" == "asc" ]]; then
        echo -e "${BOLD}Sorted by: ${SORT_BY} (${SORT_ORDER}ending)${NC}"
    fi
    
    # Prepare data
    temp_file=$(mktemp)
    
    export -f process_node
    export -f to_gi
    export -f mi_to_gi
    export -f calculate_mem_from_pods
    export SORT_BY
    
    # Selector for nodes
    if [[ "$SHOW_ALL" == true ]]; then
        SELECTOR=""
    else
        SELECTOR="--selector=!node-role.kubernetes.io/control-plane"
    fi
    
    # Get nodes and process in parallel
    kubectl get nodes $SELECTOR -o name 2>/dev/null | \
        sed 's|node/||' | \
        xargs -P $PARALLEL -I {} bash -c 'process_node "$@"' _ {} > $temp_file
    
    # Initialize totals
    total_cpu_req=0
    total_cpu_lim=0
    total_cpu_use=0
    total_cpu_cap=0
    total_mem_req=0
    total_mem_lim=0
    total_mem_use=0
    total_mem_cap=0
    node_count=0
    
    # Determine sort options
    if [[ "$SORT_BY" == "name" ]]; then
        SORT_CMD="sort -t'|' -k1"
    else
        SORT_CMD="sort -t'|' -k1 -n"
    fi
    
    if [[ "$SORT_ORDER" == "desc" ]]; then
        SORT_CMD="$SORT_CMD -r"
    fi
    
    # Output based on format
    case "$OUTPUT_FORMAT" in
        csv)
            echo "NODE,CPU_REQ,CPU_LIM,CPU_USE,CPU_%,CPU_TOTAL,MEM_REQ,MEM_LIM,MEM_USE,MEM_%,MEM_TOTAL"
            eval "$SORT_CMD $temp_file" | while IFS='|' read -r sort_val node cpu_req cpu_lim cpu_use cpu_pct cpu_total mem_req_gi mem_lim_gi mem_use_gi mem_pct mem_total_gi; do
                echo "$node,$cpu_req,$cpu_lim,$cpu_use,$cpu_pct%,$cpu_total,${mem_req_gi}Gi,${mem_lim_gi}Gi,${mem_use_gi}Gi,$mem_pct%,${mem_total_gi}Gi"
            done
            ;;
            
        json)
            echo "{"
            echo '  "timestamp": "'$(date -Iseconds)'",'
            echo '  "sort_by": "'$SORT_BY'",'
            echo '  "sort_order": "'$SORT_ORDER'",'
            echo '  "nodes": ['
            first=true
            eval "$SORT_CMD $temp_file" | while IFS='|' read -r sort_val node cpu_req cpu_lim cpu_use cpu_pct cpu_total mem_req_gi mem_lim_gi mem_use_gi mem_pct mem_total_gi; do
                [[ "$first" == false ]] && echo ","
                echo -n '    {"name":"'$node'","cpu_req":"'$cpu_req'","cpu_lim":"'$cpu_lim'","cpu_use":"'$cpu_use'","cpu_pct":'$cpu_pct',"cpu_total":'$cpu_total',"mem_req_gi":'$mem_req_gi',"mem_lim_gi":'$mem_lim_gi',"mem_use_gi":'$mem_use_gi',"mem_pct":'$mem_pct',"mem_total_gi":'$mem_total_gi'}'
                first=false
            done
            echo ""
            echo "  ]"
            echo "}"
            ;;
            
        table|*)
            # Header
            printf "%-18s %-8s %-8s %-8s %-6s %-8s | %-8s %-8s %-8s %-6s %-8s\n" \
                "WORKER_NODE" "CPU_REQ" "CPU_LIM" "CPU_USE" "CPU_%" "CPU_CAP" "MEM_REQ" "MEM_LIM" "MEM_USE" "MEM_%" "MEM_CAP"
            echo "========================================================================================================"
            
            # Sort and display
            eval "$SORT_CMD $temp_file" | while IFS='|' read -r sort_val node cpu_req cpu_lim cpu_use cpu_pct cpu_total mem_req_gi mem_lim_gi mem_use_gi mem_pct mem_total_gi; do
                # Update totals
                cpu_req_val=${cpu_req%m}
                cpu_lim_val=${cpu_lim%m}
                cpu_use_val=${cpu_use%m}
                [[ -z "$cpu_req_val" ]] && cpu_req_val=0
                [[ -z "$cpu_lim_val" ]] && cpu_lim_val=0
                [[ -z "$cpu_use_val" ]] && cpu_use_val=0
                
                total_cpu_req=$((total_cpu_req + cpu_req_val))
                total_cpu_lim=$((total_cpu_lim + cpu_lim_val))
                total_cpu_use=$((total_cpu_use + cpu_use_val))
                total_cpu_cap=$(echo "$total_cpu_cap + $cpu_total" | bc 2>/dev/null || echo $total_cpu_cap)
                total_mem_req=$(echo "$total_mem_req + $mem_req_gi" | bc 2>/dev/null || echo $total_mem_req)
                total_mem_lim=$(echo "$total_mem_lim + $mem_lim_gi" | bc 2>/dev/null || echo $total_mem_lim)
                total_mem_use=$(echo "$total_mem_use + $mem_use_gi" | bc 2>/dev/null || echo $total_mem_use)
                total_mem_cap=$(echo "$total_mem_cap + $mem_total_gi" | bc 2>/dev/null || echo $total_mem_cap)
                node_count=$((node_count + 1))
                
                # Color code percentages
                if [[ "$NO_COLOR" == false ]]; then
                    if [[ ${cpu_pct%.*} -ge 80 ]]; then
                        cpu_color="${RED}"
                    elif [[ ${cpu_pct%.*} -ge 60 ]]; then
                        cpu_color="${YELLOW}"
                    else
                        cpu_color="${GREEN}"
                    fi
                    
                    if [[ ${mem_pct%.*} -ge 80 ]]; then
                        mem_color="${RED}"
                    elif [[ ${mem_pct%.*} -ge 60 ]]; then
                        mem_color="${YELLOW}"
                    else
                        mem_color="${GREEN}"
                    fi
                else
                    cpu_color=""
                    mem_color=""
                fi
                
                # Format display values
                mem_req_display="${mem_req_gi}Gi"
                mem_lim_display="${mem_lim_gi}Gi"
                mem_use_display="${mem_use_gi}Gi"
                mem_cap_display="${mem_total_gi}Gi"
                
                # Truncate node name if too long
                if [[ ${#node} -gt 18 ]]; then
                    node_display="${node:0:17}.."
                else
                    node_display="$node"
                fi
                
                printf "%-18s %-8s %-8s %-8s ${cpu_color}%-6s${NC} %-8s | %-8s %-8s %-8s ${mem_color}%-6s${NC} %-8s\n" \
                    "$node_display" "$cpu_req" "$cpu_lim" "$cpu_use" "${cpu_pct}%" "$cpu_total" \
                    "${mem_req_display:0:8}" "${mem_lim_display:0:8}" "${mem_use_display:0:8}" "${mem_pct}%" "${mem_cap_display:0:8}"
                
                # Save totals to temp file
                echo "$total_cpu_req $total_cpu_lim $total_cpu_use $total_cpu_cap $total_mem_req $total_mem_lim $total_mem_use $total_mem_cap $node_count" > ${temp_file}.totals
            done
            
            # Show totals unless disabled
            if [[ "$NO_SUM" == false ]] && [[ -f ${temp_file}.totals ]]; then
                read total_cpu_req total_cpu_lim total_cpu_use total_cpu_cap total_mem_req total_mem_lim total_mem_use total_mem_cap node_count < ${temp_file}.totals
                
                echo "========================================================================================================"
                
                # Format CPU totals
                if [[ $total_cpu_req -ge 1000 ]]; then
                    total_cpu_req_fmt="$(echo "scale=1; $total_cpu_req/1000" | bc 2>/dev/null)"
                else
                    total_cpu_req_fmt="${total_cpu_req}m"
                fi
                
                if [[ $total_cpu_lim -ge 1000 ]]; then
                    total_cpu_lim_fmt="$(echo "scale=1; $total_cpu_lim/1000" | bc 2>/dev/null)"
                else
                    total_cpu_lim_fmt="${total_cpu_lim}m"
                fi
                
                if [[ $total_cpu_use -ge 1000 ]]; then
                    total_cpu_use_fmt="$(echo "scale=1; $total_cpu_use/1000" | bc 2>/dev/null)"
                else
                    total_cpu_use_fmt="${total_cpu_use}m"
                fi
                
                # Format memory totals
                total_mem_req_fmt="${total_mem_req}Gi"
                total_mem_lim_fmt="${total_mem_lim}Gi"
                total_mem_use_fmt="${total_mem_use}Gi"
                total_mem_cap_fmt="${total_mem_cap}Gi"
                
                printf "${BOLD}%-18s %-8s %-8s %-8s %-6s %-8s | %-8s %-8s %-8s %-6s %-8s${NC}\n" \
                    "TOTAL ($node_count)" \
                    "${total_cpu_req_fmt:0:8}" "${total_cpu_lim_fmt:0:8}" "${total_cpu_use_fmt:0:8}" "-" "${total_cpu_cap}" \
                    "${total_mem_req_fmt:0:8}" "${total_mem_lim_fmt:0:8}" "${total_mem_use_fmt:0:8}" "-" "${total_mem_cap_fmt:0:8}"
                
                rm -f ${temp_file}.totals
            fi
            ;;
    esac
    
    rm -f $temp_file
}

# Main execution
if [[ $WATCH_INTERVAL -gt 0 ]]; then
    # Trap Ctrl+C for clean exit
    trap 'echo -e "\nExiting..."; exit 0' INT
    
    while true; do
        clear
        echo -e "${BOLD}$(date '+%Y-%m-%d %H:%M:%S')${NC} - Refreshing every ${WATCH_INTERVAL}s (Ctrl+C to stop)"
        echo
        display_resources
        sleep $WATCH_INTERVAL
    done
else
    display_resources
fi


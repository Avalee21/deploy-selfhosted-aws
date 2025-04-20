#!/bin/bash

# Quick MinIO setup and metrics script
echo "==== MinIO Setup & Metrics Script ===="
echo "Running on host: $(hostname)"
echo "Date: $(date)"

# 1. Ensure Docker is installed and running
echo -e "\n=== DOCKER SETUP ==="
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    sudo yum update -y
    sudo yum install docker -y
    sudo systemctl start docker
    sudo systemctl enable docker
    echo "Docker installed successfully"
else
    echo "Docker is already installed"
fi

# Start Docker if not running
if ! systemctl is-active docker &> /dev/null; then
    echo "Starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
fi
echo "Docker service status: $(systemctl is-active docker)"

# 2. Setup MinIO container
echo -e "\n=== MINIO CONTAINER SETUP ==="
if ! docker ps | grep -q minio; then
    echo "MinIO container not running, setting up..."
    
    # Remove existing stopped container if it exists
    if docker ps -a | grep -q minio; then
        echo "Removing existing stopped MinIO container..."
        sudo docker rm minio
    fi
    
    # Create data directory
    sudo mkdir -p /minio/data
    
    # Start MinIO container
    echo "Starting MinIO container..."
    sudo docker run -d \
        --name minio \
        --restart always \
        -p 9000:9000 \
        -p 9001:9001 \
        -e "MINIO_ROOT_USER=minio" \
        -e "MINIO_ROOT_PASSWORD=minio123" \
        -v /minio/data:/data \
        minio/minio server /data --console-address ":9001"
else
    echo "MinIO container is already running"
fi

# 3. Check MinIO status
echo -e "\n=== MINIO STATUS CHECK ==="
if docker ps | grep -q minio; then
    echo "MinIO container: RUNNING"
    echo "Container ID: $(docker ps -q --filter name=minio)"
    echo "Container created: $(docker inspect -f '{{.Created}}' minio)"
    
    # Check if MinIO service is responding
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:9000/minio/health/live; then
        echo "MinIO health check: PASSED"
    else
        echo "MinIO health check: FAILED"
    fi
else
    echo "MinIO container is NOT running"
fi

# 4. Set up metrics collection script
echo -e "\n=== METRICS COLLECTION SETUP ==="

# Create metrics collection script
cat > /tmp/collect_metrics.sh << 'EOL'
#!/bin/bash

# Get current timestamp
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# System metrics - Updated to check for MinIO data directory
if [ -d "/minio/data" ]; then
    DISK_UTIL=$(df -h /minio/data | awk 'NR==2 {print $5}' | sed 's/%//')
    # Fallback to root filesystem if the above command returns empty
    if [ -z "$DISK_UTIL" ]; then
        DISK_UTIL=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    fi
else
    # If MinIO data directory doesn't exist, use root filesystem
    DISK_UTIL=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
fi

MEM_UTIL=$(free | grep Mem | awk '{ printf "%.2f", $3/$2 * 100 }')
CPU_UTIL=$(top -bn1 | grep "Cpu(s)" | awk '{ printf "%.2f", $2 + $4 }')

# MinIO service check
MINIO_STATUS=0
if netstat -tulpn 2>/dev/null | grep -q ":9000"; then
    MINIO_STATUS=1
fi

# MinIO health check
MINIO_HEALTH=0
if [ $MINIO_STATUS -eq 1 ]; then
    HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9000/minio/health/live)
    if [ -n "$HEALTH_CODE" ] && [ "$HEALTH_CODE" != "000" ]; then
        MINIO_HEALTH=$HEALTH_CODE
    fi
fi

# Server uptime
UPTIME=$(cat /proc/uptime | awk '{print $1}')

# Output for local viewing
echo "[$TIMESTAMP] METRICS:"
echo "- Disk: ${DISK_UTIL}%"
echo "- Memory: ${MEM_UTIL}%"
echo "- CPU: ${CPU_UTIL}%"
echo "- MinIO Status: ${MINIO_STATUS}"
echo "- MinIO Health: ${MINIO_HEALTH}"
echo "- Uptime: ${UPTIME} seconds"

# Send to CloudWatch
aws cloudwatch put-metric-data --namespace MinIO --metric-name "DiskUtilization" --value "${DISK_UTIL}" --region us-east-1
aws cloudwatch put-metric-data --namespace MinIO --metric-name "MemoryUtilization" --value "${MEM_UTIL}" --region us-east-1
aws cloudwatch put-metric-data --namespace MinIO --metric-name "CPUUtilization" --value "${CPU_UTIL}" --region us-east-1
aws cloudwatch put-metric-data --namespace MinIO --metric-name "ServiceStatus" --value "${MINIO_STATUS}" --region us-east-1
aws cloudwatch put-metric-data --namespace MinIO --metric-name "APIHealth" --value "${MINIO_HEALTH}" --region us-east-1
aws cloudwatch put-metric-data --namespace MinIO --metric-name "UptimeSeconds" --value "${UPTIME}" --region us-east-1
EOL

sudo mv /tmp/collect_metrics.sh /usr/local/bin/collect_metrics.sh
sudo chmod +x /usr/local/bin/collect_metrics.sh

# 5. Set up metrics collection as a background process
echo -e "\n=== STARTING METRICS COLLECTION ==="
sudo pkill -f "collect_metrics.sh" 2>/dev/null || true
sudo bash -c 'while true; do /usr/local/bin/collect_metrics.sh >> /var/log/minio_metrics.log 2>&1; sleep 60; done' > /dev/null 2>&1 &
echo "Metrics collection started in background (PID: $!)"
echo "Log file: /var/log/minio_metrics.log"

# 6. Show initial metrics
echo -e "\n=== CURRENT METRICS ==="
sudo /usr/local/bin/collect_metrics.sh

echo -e "\n=== SETUP COMPLETE ==="
echo "MinIO server is available at:"
echo "- API: http://$(hostname -I | awk '{print $1}'):9000"
echo "- Console: http://$(hostname -I | awk '{print $1}'):9001"
echo "  Username: minio"
echo "  Password: minio123"
echo "============================="
#!/bin/bash

echo "==== Cryptpad Metrics Collection Setup ===="
echo "Running on host: $(hostname)"
echo "Date: $(date)"

# Create metrics collection script with proper permissions
echo -e "\n=== CREATING METRICS SCRIPT ==="

sudo bash -c 'cat > /usr/local/bin/collect_cryptpad_metrics.sh << EOL
#!/bin/bash

# Get timestamp
TIMESTAMP=\$(date +"%Y-%m-%d %H:%M:%S")

# Get system metrics
CPU_UTIL=\$(top -bn1 | grep "Cpu(s)" | awk "{print \\\$2 + \\\$4}")
DISK_UTIL=\$(df -h | grep "/dev/" | grep -v "/boot" | head -1 | awk "{print \\\$5}" | sed "s/%//")
MEM_UTIL=\$(free | grep Mem | awk "{print \\\$3/\\\$2 * 100.0}")

# Check if Cryptpad is running - fixed process check
CRYPTPAD_STATUS=0
CRYPTPAD_CPU=0
CRYPTPAD_MEM=0
CRYPTPAD_UPTIME=0

if pgrep -f "node.*server" > /dev/null; then
    CRYPTPAD_STATUS=1
    # Get process stats safely - fixed command syntax
    CRYPTPAD_PID=\$(pgrep -f "node.*server" | head -1)
    if [ -n "\$CRYPTPAD_PID" ]; then
        CRYPTPAD_CPU=\$(ps -p \$CRYPTPAD_PID -o %cpu= | tr -d " " || echo "0")
        CRYPTPAD_MEM=\$(ps -p \$CRYPTPAD_PID -o rss= | tr -d " " || echo "0")
        if [ -n "\$CRYPTPAD_MEM" ] && [ "\$CRYPTPAD_MEM" != "0" ]; then
            CRYPTPAD_MEM=\$(echo "scale=2; \$CRYPTPAD_MEM / 1024" | bc -l || echo "0")
        fi
        CRYPTPAD_UPTIME=\$(ps -p \$CRYPTPAD_PID -o etimes= | tr -d " " || echo "0")
    fi
fi

# Check Cryptpad API health
CRYPTPAD_HEALTH=0
if [ \$CRYPTPAD_STATUS -eq 1 ]; then
    HEALTH_CHECK=\$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 || echo 0)
    CRYPTPAD_HEALTH=\$HEALTH_CHECK
fi

# Get datastore size if directory exists
CRYPTPAD_DATA_SIZE=0
if [ -d "/home/ubuntu/cryptpad/datastore" ]; then
    CRYPTPAD_DATA_SIZE=\$(du -sk /home/ubuntu/cryptpad/datastore 2>/dev/null | awk "{print \\\$1}" || echo 0)
fi

# Output metrics for logging
echo "[\$TIMESTAMP] CRYPTPAD METRICS:"
echo "- System CPU: \${CPU_UTIL}%"
echo "- System Disk: \${DISK_UTIL}%"
echo "- System Memory: \${MEM_UTIL}%"
echo "- Cryptpad Status: \${CRYPTPAD_STATUS}"
echo "- Cryptpad CPU: \${CRYPTPAD_CPU}%"
echo "- Cryptpad Memory: \${CRYPTPAD_MEM} MB"
echo "- Cryptpad Uptime: \${CRYPTPAD_UPTIME} seconds"
echo "- Cryptpad Health: \${CRYPTPAD_HEALTH}"
echo "- Datastore Size: \${CRYPTPAD_DATA_SIZE} KB"

# Publish metrics to CloudWatch with proper quoting
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name SystemCPUUtilization --value "\$CPU_UTIL" --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name SystemDiskUtilization --value "\$DISK_UTIL" --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name SystemMemoryUtilization --value "\$MEM_UTIL" --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name CryptpadStatus --value "\$CRYPTPAD_STATUS" --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name CryptpadCPUUtilization --value "\$CRYPTPAD_CPU" --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name CryptpadMemoryUsage --value "\$CRYPTPAD_MEM" --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name CryptpadUptime --value "\$CRYPTPAD_UPTIME" --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name CryptpadHealth --value "\$CRYPTPAD_HEALTH" --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name DatastoreSize --value "\$CRYPTPAD_DATA_SIZE" --region us-east-1
EOL'

# Make executable with correct permissions
sudo chmod +x /usr/local/bin/collect_cryptpad_metrics.sh
echo "✓ Metrics script created: /usr/local/bin/collect_cryptpad_metrics.sh"

# Create log directory with proper permissions
echo -e "\n=== SETTING UP LOG DIRECTORY ==="
sudo mkdir -p /var/log/cryptpad-metrics
sudo chmod 755 /var/log/cryptpad-metrics
echo "✓ Log directory created: /var/log/cryptpad-metrics"

# Start metrics collection as a background process
echo -e "\n=== STARTING METRICS COLLECTION ==="
# Kill any existing process
sudo pkill -f "collect_cryptpad_metrics.sh" 2>/dev/null || true
# Start new process
sudo bash -c 'while true; do /usr/local/bin/collect_cryptpad_metrics.sh >> /var/log/cryptpad-metrics/collection.log 2>&1; sleep 60; done' > /dev/null 2>&1 &
echo "✓ Metrics collection started in background (PID: $!)"
echo "✓ Log file: /var/log/cryptpad-metrics/collection.log"

# Show current metrics
echo -e "\n=== CURRENT CRYPTPAD STATUS ==="
sudo /usr/local/bin/collect_cryptpad_metrics.sh
echo ""

# Show additional helper info
echo -e "\n=== CRYPTPAD ACCESS INFORMATION ==="
PUBLIC_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

# Update the configuration file with the correct IP
if [ -f "/home/ubuntu/cryptpad/config/config.js" ]; then
    echo "Updating Cryptpad configuration with public IP..."
    sudo sed -i "s|http://127.0.0.1:3000|http://$PUBLIC_IP:3000|g" /home/ubuntu/cryptpad/config/config.js
    echo "✓ Updated Cryptpad configuration with public IP: $PUBLIC_IP"
    
    # Restart Cryptpad service to apply changes
    if systemctl is-active cryptpad &>/dev/null; then
        echo "Restarting Cryptpad service to apply changes..."
        sudo systemctl restart cryptpad
        echo "✓ Cryptpad service restarted"
    fi
else
    echo "⚠️ Cryptpad config file not found at /home/ubuntu/cryptpad/config/config.js"
    echo "   You may need to manually update the configuration with your public IP."
fi

echo "URL: http://$PUBLIC_IP:3000"
echo "To check service status: sudo systemctl status cryptpad"
echo "To view logs: sudo journalctl -u cryptpad"
echo "Metrics log: /var/log/cryptpad-metrics/collection.log"
echo "===================================="
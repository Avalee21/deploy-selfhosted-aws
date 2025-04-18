#!/bin/bash

# Script to update Cryptpad configuration with the correct IP and set up metrics collection
# Save this file as fixed_metrics_setup.sh and run it after deploying Cryptpad

# Get the public IP
PUBLIC_IP=$(curl -s ifconfig.me)
echo "Detected public IP: $PUBLIC_IP"

# Update the configuration file with the correct IP
sudo sed -i "s|http://127.0.0.1:3000|http://$PUBLIC_IP:3000|g" /home/ubuntu/cryptpad/config/config.js
echo "Updated Cryptpad configuration with public IP"

# Set up metrics collection
echo "Setting up CloudWatch metrics collection..."

# Create metrics collection script with fixed process queries
sudo bash -c "cat > /usr/local/bin/collect_cryptpad_metrics.sh << 'EOF'
#!/bin/bash

# Get system metrics
CPU_UTIL=\$(top -bn1 | grep \"Cpu(s)\" | awk '{print \$2 + \$4}')
DISK_UTIL=\$(df -h | grep \"/dev/\" | grep -v \"/boot\" | head -1 | awk '{print \$5}' | sed 's/%//')
MEM_UTIL=\$(free | grep Mem | awk '{print \$3/\$2 * 100.0}')

# Check if Cryptpad is running
CRYPTPAD_PID=\$(pgrep -f \"node.*server\" || echo \"\")
if [ -n \"\$CRYPTPAD_PID\" ]; then
    CRYPTPAD_STATUS=1
    # Get process stats safely
    CRYPTPAD_CPU=\$(ps -p \"\$CRYPTPAD_PID\" -o %cpu= | tr -d ' ' || echo \"0\")
    CRYPTPAD_MEM=\$(ps -p \"\$CRYPTPAD_PID\" -o rss= | tr -d ' ' || echo \"0\")
    if [ -n \"\$CRYPTPAD_MEM\" ]; then
        CRYPTPAD_MEM=\$(echo \"\$CRYPTPAD_MEM / 1024\" | bc -l || echo \"0\")
    else
        CRYPTPAD_MEM=0
    fi
    CRYPTPAD_UPTIME=\$(ps -p \"\$CRYPTPAD_PID\" -o etimes= | tr -d ' ' || echo \"0\")
else
    CRYPTPAD_STATUS=0
    CRYPTPAD_CPU=0
    CRYPTPAD_MEM=0
    CRYPTPAD_UPTIME=0
fi

# Check Cryptpad API health
CRYPTPAD_HEALTH=\$(curl -s -o /dev/null -w \"%{http_code}\" http://localhost:3000 || echo 0)

# Get datastore size
CRYPTPAD_DATA_SIZE=\$(du -sk /home/ubuntu/cryptpad/datastore 2>/dev/null | awk '{print \$1}' || echo 0)

# Log metrics values for debugging
echo \"[\$(date)] Metrics values:\"
echo \"CPU: \$CPU_UTIL%\"
echo \"Disk: \$DISK_UTIL%\"
echo \"Memory: \$MEM_UTIL%\"
echo \"Cryptpad Status: \$CRYPTPAD_STATUS\"
echo \"Cryptpad CPU: \$CRYPTPAD_CPU%\"
echo \"Cryptpad Memory: \$CRYPTPAD_MEM MB\"
echo \"Cryptpad Uptime: \$CRYPTPAD_UPTIME seconds\"
echo \"Cryptpad Health: \$CRYPTPAD_HEALTH\"
echo \"Datastore Size: \$CRYPTPAD_DATA_SIZE KB\"

# Publish metrics to CloudWatch
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name SystemCPUUtilization --value \$CPU_UTIL --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name SystemDiskUtilization --value \$DISK_UTIL --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name SystemMemoryUtilization --value \$MEM_UTIL --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name CryptpadStatus --value \$CRYPTPAD_STATUS --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name CryptpadCPUUtilization --value \$CRYPTPAD_CPU --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name CryptpadMemoryUsage --value \$CRYPTPAD_MEM --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name CryptpadUptime --value \$CRYPTPAD_UPTIME --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name CryptpadHealth --value \$CRYPTPAD_HEALTH --region us-east-1
aws cloudwatch put-metric-data --namespace Cryptpad --metric-name DatastoreSize --value \$CRYPTPAD_DATA_SIZE --region us-east-1
EOF"

# Make the metrics script executable
sudo chmod +x /usr/local/bin/collect_cryptpad_metrics.sh

# Test the metrics script
echo "Testing metrics collection script..."
sudo /usr/local/bin/collect_cryptpad_metrics.sh

# Create log directory
sudo mkdir -p /var/log/cryptpad-metrics

# Set up cron job to run metrics collection every minute
(crontab -l 2>/dev/null || echo "") | grep -v "collect_cryptpad_metrics" > /tmp/crontab.tmp
echo "* * * * * /usr/local/bin/collect_cryptpad_metrics.sh >> /var/log/cryptpad-metrics/collection.log 2>&1" >> /tmp/crontab.tmp
crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp

echo "CloudWatch metrics collection set up successfully"
echo ""
echo "=== Cryptpad Access Information ==="
echo "URL: http://$PUBLIC_IP:3000"
echo "To check service status: sudo systemctl status cryptpad"
echo "To view logs: sudo journalctl -u cryptpad"
echo ""
echo "CloudWatch metrics are being collected every minute"
echo "Metrics log: /var/log/cryptpad-metrics/collection.log"
#!/bin/bash

LOG_FILE="telemetry_log.txt"

# Function to display TDP from dmidecode
function display_tdp {
  echo "=== Thermal Design Power (TDP) ===" | tee -a $LOG_FILE
  TDP=$(sudo dmidecode -t processor | grep -i 'Thermal Design Power')
  if [ -z "$TDP" ]; then
    echo "TDP information not available or not supported on this system." | tee -a $LOG_FILE
  else
    echo "$TDP" | tee -a $LOG_FILE
  fi
  echo | tee -a $LOG_FILE
}

# Function to display NIC usage
function display_nic_usage {
  echo "=== Network Interface Controller (NIC) Usage ===" | tee -a $LOG_FILE
  if command -v ifstat &> /dev/null
  then
    ifstat -i eth0 1 1 | awk 'NR==3 {print "eth0 RX: " $1 " KB/s, TX: " $2 " KB/s"}' | tee -a $LOG_FILE
  else
    echo "ifstat not installed. Please install it with: sudo apt-get install ifstat" | tee -a $LOG_FILE
  fi
  echo | tee -a $LOG_FILE
}

# Function to display memory usage
function display_memory_usage {
  echo "=== Memory Usage ===" | tee -a $LOG_FILE
  free -h | tee -a $LOG_FILE
  echo | tee -a $LOG_FILE
}

# Function to display CPU usage
function display_cpu_usage {
  echo "=== CPU Usage ===" | tee -a $LOG_FILE
  top -bn1 | grep "Cpu(s)" | awk '{print "CPU Usage: " $2 + $4 "%"}' | tee -a $LOG_FILE
  echo | tee -a $LOG_FILE
}

# Function to display Docker container stats
function display_docker_stats {
  echo "=== Docker Container Stats ===" | tee -a $LOG_FILE
  docker stats --no-stream | tee -a $LOG_FILE
  echo | tee -a $LOG_FILE
}

# Function to setup and display cAdvisor metrics
function setup_cadvisor {
  if [ ! $(docker ps -q -f name=cadvisor) ]; then
    echo "=== Setting up cAdvisor ===" | tee -a $LOG_FILE
    docker run \
      --volume=/:/rootfs:ro \
      --volume=/var/run:/var/run:rw \
      --volume=/sys:/sys:ro \
      --volume=/var/lib/docker/:/var/lib/docker:ro \
      --publish=8080:8080 \
      --detach=true \
      --name=cadvisor \
      gcr.io/cadvisor/cadvisor:latest
    echo "cAdvisor is running on http://localhost:8080" | tee -a $LOG_FILE
    echo | tee -a $LOG_FILE
  else
    echo "cAdvisor is already running on http://localhost:8080" | tee -a $LOG_FILE
    echo | tee -a $LOG_FILE
  fi
}

# Function to stress the system using Docker
function stress_docker {
  echo "=== Stressing the System with Docker Containers ===" | tee -a $LOG_FILE

  TOTAL_CPUS=$(nproc)

  for utilization in 50 70 100; do
    echo "Running stress-ng in Docker with ${utilization}% CPU utilization." | tee -a $LOG_FILE
    container_name="stress${utilization}"
    num_workers=$(echo "scale=0; $TOTAL_CPUS * $utilization / 100" | bc)

    docker run -d --name=${container_name} --rm alpine sh -c "apk add --no-cache stress-ng && stress-ng --cpu ${num_workers} --timeout 60s"
    sleep 10  # Wait to allow stress to take effect

    echo "=== Docker Stats at ${utilization}% Utilization ===" | tee -a $LOG_FILE
    docker stats --no-stream | tee -a $LOG_FILE
    display_nic_usage
    display_memory_usage

    # Get CPU usage directly from docker stats for the specific container
    container_cpu=$(docker stats ${container_name} --no-stream --format "{{.CPUPerc}}")
    echo "Container ${container_name} CPU Usage: ${container_cpu}" | tee -a $LOG_FILE

    docker stop ${container_name} || true  # Ensure container is stopped
    docker rm ${container_name} || true  # Ensure container is removed
    echo | tee -a $LOG_FILE
  done
}

# Main function to display all telemetry data and stress the system
function display_all_telemetry {
  display_tdp
  display_docker_stats
  setup_cadvisor
  stress_docker
}

# Execute the main function
display_all_telemetry
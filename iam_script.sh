#!/bin/bash



# Log file
LOG_FILE="iam_setup.log"

# Function to log actions
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo "$1"
}

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Initialize log file
> "$LOG_FILE"
log_action "Starting user and group setup"

# Determine input file
INPUT_FILE="users.txt"
if [ $# -eq 1 ]; then
    INPUT_FILE="$1"
    log_action "Using input file: $INPUT_FILE"
fi

# Check for password complexity
check_password_complexity() {
    local password="$1"
    local username="$2"
    
    # Password must be at least 8 characters
    if [ ${#password} -lt 8 ]; then
        return 1
    fi
    
    # Password must contain at least one uppercase letter
    if ! echo "$password" | grep -q [A-Z]; then
        return 1
    fi
    
    # Password must contain at least one lowercase letter
    if ! echo "$password" | grep -q [a-z]; then
        return 1
    fi
    
    # Password must contain at least one digit
    if ! echo "$password" | grep -q [0-9]; then
        return 1
    fi
    
    # Password must contain at least one special character
    if ! echo "$password" | grep -q '[@#$%^&*()_+!]'; then
        return 1
    fi
    
    # Password should not contain username
    if echo "$password" | grep -qi "$username"; then
        return 1
    fi
    
    return 0
}

# 1. Create groups
create_group() {
    local group="$1"
    
    # Check if group exists
    if grep -q "^$group:" /etc/group; then
        log_action "Group '$group' already exists"
    else
        groupadd "$group"
        if [ $? -eq 0 ]; then
            log_action "Created group '$group'"
        else
            log_action "Failed to create group '$group'"
        fi
    fi
}

# 2. Create users with all required settings
create_user() {
    local username="$1"
    local fullname="$2"
    local group="$3"
    local default_password="ChangeMe123"
    local complex_password="ChangeMe123!@#"
    
    # Create group if it doesn't exist
    create_group "$group"
    
    # Check if user exists
    if id "$username" &>/dev/null; then
        log_action "User '$username' already exists"
    else
        # Create user with home directory
        useradd -m -c "$fullname" -g "$group" "$username"
        if [ $? -eq 0 ]; then
            log_action "Created user '$username' ($fullname) in group '$group'"
            
            # Check password complexity
            if check_password_complexity "$default_password" "$username"; then
                # Set temporary password
                echo "${username}:${default_password}" | chpasswd
                log_action "Set temporary password for '$username'"
            else
                # Set a more complex password
                echo "${username}:${complex_password}" | chpasswd
                log_action "Set complex temporary password for '$username'"
            fi
            
            # Force password change on first login
            passwd -e "$username"
            log_action "Forced password change on first login for '$username'"
            
            # Set permissions on home directory
            chmod 700 "/home/$username"
            log_action "Set permissions 700 on /home/$username"
        else
            log_action "Failed to create user '$username'"
        fi
    fi
}

# Process input file
if [ -f "$INPUT_FILE" ]; then
    log_action "Processing $INPUT_FILE file"
    
    # Skip header line if it exists
    HEADER=$(head -n 1 "$INPUT_FILE")
    if [[ "$HEADER" == "username,fullname,group" ]]; then
        log_action "Skipping header line"
        SKIP_HEADER=1
    else
        SKIP_HEADER=0
    fi
    
    # Process each line
    LINE_NUM=0
    while IFS=, read -r username fullname group || [ -n "$username" ]; do
        LINE_NUM=$((LINE_NUM + 1))
        
        # Skip header if needed
        if [ $SKIP_HEADER -eq 1 ] && [ $LINE_NUM -eq 1 ]; then
            continue
        fi
        
        # Skip empty lines and comments
        if [[ -z "$username" || "$username" == \#* ]]; then
            continue
        fi
        
        create_user "$username" "$fullname" "$group"
    done < "$INPUT_FILE"
    
    log_action "Finished processing $INPUT_FILE file"
else
    log_action "Error: $INPUT_FILE file not found"
    exit 1
fi

log_action "User and group setup completed successfully"
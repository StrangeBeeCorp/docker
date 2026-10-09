#!/bin/bash

# Function for informational messages
info() {
    echo -e "\033[1;34m[*] $1 \033[0m"
}

# Function for success messages
success() {
    echo -e "\033[1;32m[✔] $1 \033[0m"
}

# Function for warning messages
warning() {
    echo -e "\033[1;33m[!] $1 \033[0m"
}

# Function for error messages
error() {
    echo -e "\033[1;31m/!\ $1 \033[0m" >&2
}
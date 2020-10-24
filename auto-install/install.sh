#!/usr/bin/env bash

# Speaker-Select Installation Script
# Many thanks to the PiVPN project (pivpn.io) for much of the inspiration for this script
# Run from https://raw.githubusercontent.com/nebhead/spkr-select/master/auto-install/install.sh
#
# Install with this command (from your Pi):
#
# curl https://raw.githubusercontent.com/nebhead/spkr-select/master/auto-install/install.sh | bash
#

# Must be root to install
if [[ $EUID -eq 0 ]];then
    echo "You are root."
else
    echo "SUDO will be used for the install."
    # Check if it is actually installed
    # If it isn't, exit because the install cannot complete
    if [[ $(dpkg-query -s sudo) ]];then
        export SUDO="sudo"
        export SUDOE="sudo -E"
    else
        echo "Please install sudo or run this as root."
        exit 1
    fi
fi

# Find the rows and columns. Will default to 80x24 if it can not be detected.
screen_size=$(stty size 2>/dev/null || echo 24 80)
rows=$(echo $screen_size | awk '{print $1}')
columns=$(echo $screen_size | awk '{print $2}')

# Divide by two so the dialogs take up half of the screen.
r=$(( rows / 2 ))
c=$(( columns / 2 ))
# If the screen is small, modify defaults
r=$(( r < 20 ? 20 : r ))
c=$(( c < 70 ? 70 : c ))

# Display the welcome dialog
whiptail --msgbox --backtitle "Welcome" --title "Speaker-Select Automated Installer" "This installer will transform your Raspberry Pi into a smart speaker-selector.  NOTE: This installer is intended to be run on a fresh install of Raspberry Pi OS (Buster)." ${r} ${c}

# Starting actual steps for installation
clear
echo "*************************************************************************"
echo "**                                                                     **"
echo "**      Running Apt Update... (This could take several minutes)        **"
echo "**                                                                     **"
echo "*************************************************************************"
$SUDO apt update
clear
echo "*************************************************************************"
echo "**                                                                     **"
echo "**      Running Apt Upgrade... (This could take several minutes)       **"
echo "**                                                                     **"
echo "*************************************************************************"
$SUDO apt upgrade -y

# Install dependancies
clear
echo "*************************************************************************"
echo "**                                                                     **"
echo "**      Installing Dependancies... (This could take several minutes)   **"
echo "**                                                                     **"
echo "*************************************************************************"
$SUDO apt install python3-dev python3-pip python3-rpi.gpio nginx git gunicorn3 supervisor -y
$SUDO pip3 install flask

# Grab project files
clear
echo "*************************************************************************"
echo "**                                                                     **"
echo "**      Cloning Speaker-Select from GitHub...                          **"
echo "**                                                                     **"
echo "*************************************************************************"
cd ~
git clone https://github.com/nebhead/spkr-select

### Setup nginx to proxy to gunicorn
clear
echo "*************************************************************************"
echo "**                                                                     **"
echo "**      Configuring nginx...                                           **"
echo "**                                                                     **"
echo "*************************************************************************"
# Move into install directory
cd ~/spkr-select

# Delete default configuration
$SUDO rm /etc/nginx/sites-enabled/default

# Copy configuration file to nginx
$SUDO cp spkr-select.nginx /etc/nginx/sites-available/spkr-select

# Create link in sites-enabled
$SUDO ln -s /etc/nginx/sites-available/spkr-select /etc/nginx/sites-enabled

whiptail --msgbox --backtitle "SSL Certs" --title "Speaker-Select Automated Installer" "The script will now open a text editor to edit a configuration file for the cert generation.  Fill in the defaults you'd like the signing to use for your instance and when finished, press CTRL+x to save and exit." ${r} ${c}

cd ~/spkr-select/certs

# Modify the localhost configuration file
nano localhost.conf

# Create public and private key pairs based on localhost.conf information
$SUDO openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout localhost.key -out localhost.crt -config localhost.conf

# Move the public key to the /etc/ssl/certs directory
$SUDO mv localhost.crt /etc/ssl/certs/localhost.crt
# Move the private key to the /etc/ssl/private directory
$SUDO mv localhost.key /etc/ssl/private/localhost.key

# Restart nginx
$SUDO service nginx restart

### Setup Supervisor to Start Apps on Boot / Restart on Failures
clear
echo "*************************************************************************"
echo "**                                                                     **"
echo "**      Configuring Supervisord...                                     **"
echo "**                                                                     **"
echo "*************************************************************************"

# Copy configuration files (control.conf, webapp.conf) to supervisor config directory
# NOTE: If you used a different directory for the installation then make sure you edit the *.conf files appropriately
cd ~/spkr-select/supervisor

$SUDO cp *.conf /etc/supervisor/conf.d/

SVISOR=$(whiptail --title "Would you like to enable the supervisor WebUI?" --radiolist "This allows you to check the status of the supervised processes via a web browser, and also allows those processes to be restarted directly from this interface. (Recommended)" 20 78 2 "ENABLE_SVISOR" "Enable the WebUI" ON "DISABLE_SVISOR" "Disable the WebUI" OFF 3>&1 1>&2 2>&3)

if [[ $SVISOR = "ENABLE_SVISOR" ]];then
   echo " " | sudo tee -a /etc/supervisor/supervisord.conf > /dev/null
   echo "[inet_http_server]" | sudo tee -a /etc/supervisor/supervisord.conf > /dev/null
   echo "port = 9001" | sudo tee -a /etc/supervisor/supervisord.conf > /dev/null
   USERNAME=$(whiptail --inputbox "Choose a username [default: user]" 8 78 user --title "Choose Username" 3>&1 1>&2 2>&3)
   echo "username = " $USERNAME | sudo tee -a /etc/supervisor/supervisord.conf > /dev/null
   PASSWORD=$(whiptail --passwordbox "Enter your password" 8 78 --title "Choose Password" 3>&1 1>&2 2>&3)
   echo "password = " $PASSWORD | sudo tee -a /etc/supervisor/supervisord.conf > /dev/null
   whiptail --msgbox --backtitle "Supervisor WebUI Setup" --title "Setup Completed" "You now should be able to access the Supervisor WebUI at http://your.ip.address.here:9001 with the username and password you have chosen." ${r} ${c}
else
   echo "No WebUI Setup."
fi

echo "Starting Supervisor Service..."
# If supervisor isn't already running, startup Supervisor
$SUDO service supervisor start

### Setup LIRC for IR Remote Control Support
clear
echo "*************************************************************************"
echo "**                                                                     **"
echo "**      Configuring LIRC...                                            **"
echo "**                                                                     **"
echo "*************************************************************************"

LIRC=$(whiptail --title "Would you like to enable LIRC?" --radiolist "This option allows you to control the speaker selector via an IR remote control. (NOTE: This install ONLY WORKS WITH Raspberry Pi OS Buster 08-2020.  Will NOT work with prior versions or with Stretch as many configurations have changed.)" 20 78 2 "ENABLE_LIRC" "Enable LIRC and install dependancies." ON "DISABLE_LIRC" "Disable LIRC" OFF 3>&1 1>&2 2>&3)

if [[ $LIRC = "ENABLE_LIRC" ]];then
    cd ~/spkr-select 
    $SUDO apt install lirc liblircclient-dev -y
    # Add LIRC configs to system files
    echo "dtoverlay=gpio-ir,gpio_pin=02" | sudo tee -a /boot/config.txt > /dev/null
    # Update the following lines in /etc/lirc/lirc_options.conf:
    #    driver    = default
    #    device    = /dev/lirc0
    $SUDO sed -i 's|devinput|default|' /etc/lirc/lirc_options.conf
    $SUDO sed -i 's|auto|/dev/lirc0|' /etc/lirc/lirc_options.conf
    cd ~/spkr-select
    $SUDO cp hardware.conf /etc/lirc/hardware.conf
    $SUDO cp lircd.conf /etc/lirc/lircd.conf
    $SUDO cp lircrc.txt /etc/lirc/.lircrc
    $SUDO cp lircrc.txt .lircrc
    #$SUDO pip3 install python3-lirc # This would normally work, but as of Raspberry Pi OS Buster, this package is not available
    # Instead of the above command, we need to pull the source and build/install it locally 
    $SUDO pip3 install Cython
    git clone https://github.com/tompreston/python-lirc.git
    cd python-lirc 
    $SUDO python3 setup.py build
    $SUDO python3 setup.py install 
    cd ~/spkr-select
    # Enable LIRC in Control.py
    sed -i 's|LIRC_Enabled = False|LIRC_Enabled = True|' control.py
else
   echo "Declining LIRC setup."
fi

# Rebooting
whiptail --msgbox --backtitle "Install Complete / Reboot Required" --title "Installation Completed - Rebooting" "Congratulations, the installation is complete.  At this time, we will perform a reboot and your application should be ready.  You should be able to access your application by opening a browser on your PC or other device and using the IP address for this Pi.  Enjoy!  Note: LIRC support requires extra configuration - see readme.md." ${r} ${c}
clear
$SUDO reboot

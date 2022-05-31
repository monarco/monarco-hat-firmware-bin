#!/bin/bash

# monarco-eeprom.sh
# HAT ID EEPROM update tool for the Monarco HAT board.
#
# https://www.monarco.io
# https://github.com/monarco/
#
# Copyright 2022 REX Controls s.r.o. http://www.rexcontrols.com
# Author: Vlastimil Setka
#
#  This file is covered by the BSD 3-Clause License
#    see LICENSE.txt in the root directory of this project
#    or <https://opensource.org/licenses/BSD-3-Clause>
#

set -e

GPIO_WR_ENABLE=26
I2CDEV=3

SCRIPTPATH=$(dirname $(readlink -f $0))

echo "Monarco HAT ID EEPROM flash tool, version 1.3"
echo "(c) REX Controls 2022, http://www.rexcontrols.com"
echo ""

if [ $EUID -ne 0 ]; then
  echo "ERROR: Root user required for Monarco HAT EEPROM ID update, UID $EUID detected! Please run as root. Exiting." 1>&2
  exit 3
fi

MODE=$1
FILE=$2

if [ "$MODE" == "flash" ]; then

  if [ ! -f "$FILE" ]; then
    echo "ERROR: Invalid file '$FILE'" 1>&2
    exit 2
  fi

elif [ "$MODE" == "update" ]; then

  if [ ! -f /proc/device-tree/hat/uuid ]; then
    echo "ERROR: Missing HAT ID in /proc" 1>&2
    exit 3
  fi

  if [ "$(cat /proc/device-tree/hat/uuid | tr '\0' '\n')" != "fe0f39bf-7c03-4eb6-9a91-df861ae5abcd" ]; then
    echo "ERROR: Invalid HAT UUID in /proc" 1>&2
    exit 3
  fi

  if [[ "$(uname -r)" =~ ^([0-9]).([0-9]+).([0-9]+) ]]; then
    KERNEL_MAJOR=${BASH_REMATCH[1]}
    KERNEL_MINOR=${BASH_REMATCH[2]}
    echo KERNEL_MAJOR: \"$KERNEL_MAJOR\" KERNEL_MINOR: \"$KERNEL_MINOR\"
  else
    echo "ERROR: Kernel detection failed" 1>&2
    exit 3
  fi

  if [[ "$(cat /proc/device-tree/hat/product_ver | tr '\0' '\n')" =~ 0x([0-9])([0-9][0-9][0-9]) ]]; then
    HAT_VER_DT=${BASH_REMATCH[1]}
    HAT_VER_HW=${BASH_REMATCH[2]}
    echo HAT_VER_DT: \"$HAT_VER_DT\" HAT_VER_HW: \"$HAT_VER_HW\"
  else
    echo "ERROR: Invalid HAT PRODUCT_VER in /proc" 1>&2
    exit 3
  fi

  if [ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -eq 4 ]; then

    if [ "$HAT_VER_DT" == "0" ]; then
      echo; echo "EEPROM MATCHING KERNEL, OK, EXITING."; echo
      exit 0
    else
      FILE=$SCRIPTPATH/eeprom-bin/eeprom-v0${HAT_VER_HW}-monarco-hat-1.eep
      printf "\nEEPROM NEEDS DOWNGRADE, CONTINUE? TYPE yes: "
      read READ
      [ "$READ" == "yes" ] || ( echo "Cancelled."; exit 9 )
    fi

  elif ( [ "$KERNEL_MAJOR" -eq 4 ] && [ "$KERNEL_MINOR" -ge 9 ] ) || ( [ "$KERNEL_MAJOR" -gt 4 ] ); then

    if [ "$HAT_VER_DT" == "1" ]; then
      echo; echo "EEPROM MATCHING KERNEL, OK, EXITING."; echo
      exit 0
    else
      FILE=$SCRIPTPATH/eeprom-bin/eeprom-v1${HAT_VER_HW}-monarco-hat-4-9.eep
      printf "\nEEPROM NEEDS UPGRADE, CONTINUE? TYPE yes: "
      read READ
      [ "$READ" == "yes" ] || ( echo "Cancelled."; exit 9 )
    fi

  else

    echo "ERROR: Unsupported kernel version" 1>&2
    exit 3

  fi

  echo

else

  echo "Usage:"
  echo "    $0 update"
  echo "    $0 flash <.eep file>"
  exit 1

fi

modprobe i2c_dev

dtoverlay i2c-gpio bus=$I2CDEV i2c_gpio_sda=0 i2c_gpio_scl=1
rc=$?
if [ $rc != 0 ]; then
  echo "ERROR: loading dtoverlay i2c-gpio failed (rc $rc), exiting"
  exit 4
fi

if [ ! -e /sys/class/i2c-adapter/i2c-$I2CDEV ]; then
  echo "ERROR: Missing i2c-$I2CDEV device, something failed, exiting"
  exit 4
fi

modprobe at24

if [ ! -d "/sys/class/i2c-adapter/i2c-$I2CDEV/$I2CDEV-0050" ]; then
  echo "24c32 0x50" > /sys/class/i2c-adapter/i2c-$I2CDEV/new_device
fi

if [ ! -e "/sys/class/i2c-adapter/i2c-$I2CDEV/$I2CDEV-0050/eeprom" ]; then
  echo "ERROR: missing eeprom device file, something failed, exiting"
  exit 5
fi

if [ ! -e "/sys/class/gpio/gpio${GPIO_WR_ENABLE}" ]; then
  echo "${GPIO_WR_ENABLE}" > /sys/class/gpio/export
fi
echo "out" > /sys/class/gpio/gpio${GPIO_WR_ENABLE}/direction
echo "0" > /sys/class/gpio/gpio${GPIO_WR_ENABLE}/value

echo "# Writing EEPROM:"

dd if=$FILE of=/sys/class/i2c-adapter/i2c-$I2CDEV/$I2CDEV-0050/eeprom status=progress
rc=$?
if [ $rc != 0 ]; then
  echo "ERROR: ERITE FAILED (rc $rc), exiting"
  exit 6
fi

echo ""
echo "# Checking EEPROM:"

TMPFILE=$(mktemp)
dd of=$TMPFILE if=/sys/class/i2c-adapter/i2c-$I2CDEV/$I2CDEV-0050/eeprom status=progress
rc=$?
if [ $rc != 0 ]; then
  echo "ERROR: ERITE FAILED (rc $rc), exiting"
  exit 7
fi

echo "in" > /sys/class/gpio/gpio${GPIO_WR_ENABLE}/direction

RES=0
cmp -n $(stat --printf=%s "$FILE") "$FILE" "$TMPFILE" || RES=$?

echo ""

if [ $RES != 0 ]; then
  echo "ERROR: EEPROM Check failed!"
  exit 10
else
  echo "EEPROM FLASH FINISHED OK!"
  echo "REBOOT YOUR DEVICE TO TAKE EFFECT."
  echo
fi

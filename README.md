# Monarco HAT Flash Firmware Downloader

## Runtime Requirements

* perl
* libdigest-crc-perl
* libdevice-serialport-perl

```
sudo apt update
sudo apt instal perl libdigest-crc-perl libdevice-serialport-perl
```

## Usage

### Quick Help

```
$ sudo ./monarco-flash.pl
Monarco HAT Flash Firmware Downloader, version 1.1
(c) REX Controls 2016, http://www.rexcontrols.com

Usage:
    ./monarco-flash.pl [options] flash <firmware-image-file>
    ./monarco-flash.pl [options] getserial

Options defaults: --uart_device=/dev/ttyAMA0 --gpio_reset=21 --gpio_bootloader=20
```

### Checking Monarco HAT MCU ID

```
$ sudo ./monarco-flash.pl getserial
Monarco HAT Flash Firmware Downloader, version 1.1
(c) REX Controls 2016, http://www.rexcontrols.com

MCU Bootloader ID: [1.60 ChipID: 247DBC0257516B45]
```

### Flashing Firmware

```
$ ./monarco-flash.pl flash ./firmware-bin/fw-monarco-hat-2004.bin
Monarco HAT Flash Firmware Downloader, version 1.1
(c) REX Controls 2016, http://www.rexcontrols.com

HAT ID detected:
  Vendor: REX Controls
  Product: Monarco HAT
  Product ID: 0x0001
  Product VER: 0x0103
  UUID: fe0f39bf-7c03-4eb6-9a91-df861ae5abcd

Serial device /dev/ttyAMA0 check OK.

MCU Bootloader ID: [1.60 ChipID: 247DBC0257516B45]

Press ENTER to continue ...
XModem: Start, waiting for handshake
XModem: Handshake success
XModem: Sending: .................................................................................................................................................................

CRC RESULT: [18] c--CRC: 0000BB5C--

OK!
```

#!/usr/bin/env perl

# monarco-flash.pl
# A firmware update tool for the Monarco HAT board.
#
# The EFM32 MCU on Monarco HAT is equipped with a preloaded bootloader,
# which can be activated by logic 1 on the SWCLK pin after MCU reset.
# Then it communicates via UART with baudrate autodetection.
# The UART is connected to RPi's ttyAMA0.
#
# Copyright 2016 REX Controls s.r.o. http://www.rexcontrols.com
# Author: Vlastimil Setka
#
#  This file is covered by the BSD 3-Clause License
#    see LICENSE.txt in the root directory of this project
#    or <https://opensource.org/licenses/BSD-3-Clause>
#

use strict;

use FindBin;
use lib "$FindBin::Bin/libperl";

use Carp;
use Fcntl;
use IO::Handle;
use Device::SerialPort;
use Device::SerialPort::Xmodem;
use Time::HiRes qw(usleep);
use Fuser;

# --- CONFIG OPTIONS ---

my $config = {
    'uart_device' => '/dev/ttyAMA0',
    'gpio_reset' => '21',
    'gpio_bootloader' => '20',
    'noask' => 0,
    'debug' => 0,
    'hat_uuid' => 'fe0f39bf-7c03-4eb6-9a91-df861ae5abcd'
};

# --- OUTPUT VERBOSITY ---

my $MSG_INFO_ENABLE = 1;

# --- CONSTANTS ---

my $gpio_path = '/sys/class/gpio/';
my $dt_hat_path = '/proc/device-tree/hat/';

# --- INIT ---

msg_info("Monarco HAT Flash Firmware Downloader, version 1.1\n");
msg_info("(c) REX Controls 2016, http://www.rexcontrols.com\n");
msg_info("\n");

my $EUID = $<;
if ($EUID != 0) {
    print STDERR "ERROR: Root user required for Monarco HAT flash, UID $EUID detected! Please run as root. Exiting.\n\n";
    exit 1;
}

# --- CONFIG ARGUMENTS ---

while ($ARGV[0] =~ /^--([a-z0-9_]+)=(\S+)$/) {
    if (defined $config->{$1}) {
        $config->{$1} = $2;
    }
    else {
        print STDERR "ERROR: Unknown option argument '$1'. Exiting.\n\n";
        exit 99;
    }
    shift @ARGV;
}

# --- OPERATIONAL ARGUMENTS ---

my $FILE;
my $OP = $ARGV[0];

if ($OP eq "flash") {
    $FILE = $ARGV[1];
} elsif ($OP eq "getserial") {
    $MSG_INFO_ENABLE = 0;
} else {
    $OP = undef;
}

# --- MAIN ---

if ((not defined $OP) || (($OP eq "flash") && (not defined $FILE))) {
    print "Usage:\n";
    print "    $0 [options] flash <firmware-image-file>\n";
    print "    $0 [options] getserial\n\n";
    print "Options defaults: --uart_device=/dev/ttyAMA0 --gpio_reset=21 --gpio_bootloader=20\n\n";
    exit 100;
}

if (($OP eq "flash") && (! -r $FILE)) {
    print STDERR "ERROR: Invalid file '$FILE'! Exiting.\n\n";
    exit 7;
}

if (! -c $config->{'uart_device'}) {
    print STDERR "ERROR: Serial device " . $config->{'uart_device'} . " is not a valid device! Exiting.\n\n";
    exit 2;
}

my $hat_id = {};
if (-e $dt_hat_path) {
    foreach ('vendor', 'product', 'product_id', 'product_ver', 'uuid') {
        $hat_id->{$_} = file_read($dt_hat_path . $_);
    }

    msg_info("HAT ID detected:\n");
    msg_info("  Vendor: " . $hat_id->{'vendor'} . "\n");
    msg_info("  Product: " . $hat_id->{'product'} . "\n");
    msg_info("  Product ID: " . $hat_id->{'product_id'} . "\n");
    msg_info("  Product VER: " . $hat_id->{'product_ver'} . "\n");
    msg_info("  UUID: " . $hat_id->{'uuid'} . "\n");
    msg_info("\n");
} else {
    # TODO: allow check skip/override
    print STDERR "ERROR: Missing Monarco HAT ID in device-tree! ID EEPROM broken? Exiting.\n\n";
    exit 3;
}

if ($hat_id->{'uuid'} ne $config->{'hat_uuid'}) {
    # TODO: allow check skip/override
    print STDERR "ERROR: Bad HAT UUID in device-tree! Exiting.\n\n";
    exit 4;
}

my $cmdline = file_read('/proc/cmdline');
my $cmdlineconsole = $config->{'uart_device'} =~ s/\/dev\///r;
if ($cmdline =~ /console=$cmdlineconsole/) {
    print STDERR "ERROR: Detected kernel console on $cmdlineconsole, please fix /boot/cmdline.txt! Exiting.\n\n";
    exit 5;
}

my $fuser = Fuser->new();
my @procs = $fuser->fuser($config->{'uart_device'});
if (scalar @procs > 0) {
    print STDERR "ERROR: Serial device " . $config->{'uart_device'} . " in use by process:\n";
    foreach my $proc (@procs) {
        print STDERR "  ", $proc->pid(), " ", $proc->user(), " ", $proc->cmd(), "\n";
    }
    print STDERR "Exiting.\n\n";
    exit 6;
} else {
    msg_info("Serial device " . $config->{'uart_device'} . " check OK.\n\n");
}

gpio_init();

$SIG{'INT'} = sub { print STDERR "\nEXITING\n"; gpio_bootloader_off(); exit 255; };

gpio_bootloader_on();
gpio_reset_trigger();
usleep(100000);

eval {

my $uart = Device::SerialPort->new($config->{'uart_device'}) || croak "serial port open failed";
$uart->baudrate(115200);
$uart->parity('none');
$uart->databits(8);
$uart->stopbits(1);
$uart->handshake('none');
$uart->write_settings() || croak "serial port settings failed";

# purge buffer
my ($count_in, $string_in) = $uart->read(255);

# trigger bootloader info
$uart->write("\n");
usleep(100000);
$uart->write("\n");
usleep(100000);

# read bootloader reply
my ($count_in, $string_in) = $uart->read(255);

# sanitize
$string_in =~ tr/\x20-\x7f//cd;
$string_in =~ tr/\?//d;

if ($count_in == 0) {
    die "Monarco HAT unresponsible.";
}

print "MCU Bootloader ID: [$string_in]\n\n";

if (!($string_in =~ /^\d+\.\d+\s+\S+\s+[0-9A-Z]{16}+$/)) {
    die "Monarco HAT invalid response.";
}

if ($OP eq "getserial") {
}

if ($OP eq "flash") {
    if ($config->{'noask'} == 0) {
        print "Press ENTER to continue ...";
        <STDIN>;
    }

    $uart->write("u");

    usleep(250000);
    my ($count_in, $string_in) = $uart->read(10); # flush 'u\r\nReady\r\n'

    $Device::SerialPort::Xmodem::Send::DEBUG = $config->{'debug'};
    my $send = Device::SerialPort::Xmodem::Send->new(port => $uart);
    my $result = $send->start($FILE);

    if ($result != 1) {
        die "XMODEM FAILED: $result";
    }

    $uart->write("c");
    $uart->write_drain();
    usleep(250000);
    my ($count_in, $string_in) = $uart->read(255);
    $string_in =~ s/[^\x20-\x7f]/-/gd;
    print "\nCRC RESULT: [$count_in] $string_in\n\n";

    print "OK!\n\n";
}

$uart->close();

};

my $rc = 0;

if ($@) {
    print STDERR "\nERROR: ", $@, " Exiting.\n\n";
    $rc = 127;
}

gpio_bootloader_off();
gpio_reset_trigger();

exit $rc;

# --- COMMON FUNCTIONS ---

sub msg_info
{
    my $msg = shift;
    return unless $MSG_INFO_ENABLE;
    print $msg;
}

sub gpio_init
{
    if (! -e $gpio_path . 'gpio' . $config->{'gpio_reset'}) {
        file_write($gpio_path . 'export', $config->{'gpio_reset'});
    }

    if (! -e $gpio_path . 'gpio' . $config->{'gpio_bootloader'}) {
        file_write($gpio_path . 'export', $config->{'gpio_bootloader'});
    }
}

sub gpio_bootloader_on
{
    file_write($gpio_path . 'gpio' . $config->{'gpio_bootloader'} . '/direction', 'out');
    file_write($gpio_path . 'gpio' . $config->{'gpio_bootloader'} . '/value', '1');
}

sub gpio_bootloader_off
{
    file_write($gpio_path . 'gpio' . $config->{'gpio_bootloader'} . '/direction', 'in');
}

sub gpio_reset_trigger
{
    file_write($gpio_path . 'gpio' . $config->{'gpio_reset'} . '/direction', 'out');
    file_write($gpio_path . 'gpio' . $config->{'gpio_reset'} . '/value', '0');
    file_write($gpio_path . 'gpio' . $config->{'gpio_reset'} . '/direction', 'in');
}

sub file_write
{
    my ($file, $value) = @_;
    sysopen(FILE, $file, O_WRONLY) || croak "open error";
    FILE->autoflush(1);
    print(FILE $value) || croak "write error";
    close FILE;
}

sub file_read
{
    my ($file) = @_;
    sysopen(FILE, $file, O_RDONLY) || croak "open error";
    my $value = <FILE> || croak "read error";
    $value =~ s/\x0//g;
    close FILE;
    return $value;
}

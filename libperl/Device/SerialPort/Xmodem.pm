use 5.004;
use strict;
use warnings;

our $VERSION = '1.04';

# Preloaded methods go here.

package Device::SerialPort::Xmodem::Constants;

# Define constants used in xmodem blocks
sub nul        () { 0x00 } # ^@
sub soh        () { 0x01 } # ^A
sub stx        () { 0x02 } # ^B
sub eot        () { 0x04 } # ^D
sub ack        () { 0x06 } # ^E
sub nak        () { 0x15 } # ^U
sub can        () { 0x18 } # ^X
sub C          () { 0x43 }
sub ctrl_z     () { 0x1A } # ^Z


package Device::SerialPort::Xmodem::Block;

use overload q[""] => \&to_string;
use Digest::CRC;

# Create a new block object
sub new {
	my($proto, $num, $data, $length) = @_;
	my $class = ref $proto || $proto;

	# Check is block had required number of parameters
	if (@_ < 3) {
		# Return 0 length block
		$length = 0;
	} else {
		# Define block type (128 or 1k chars) if not specified
		$length ||= ( length $data > 128 ? 1024 : 128 );
	}

	# Define structure of a Xmodem transfer block object
	my $self = {
		number  => defined $num ? $num : 0,
		'length'=> $length,
		data    => defined $data ? substr($data, 0, $length) : "",      # Blocks are limited to 128 or 1024 chars
	};

	bless $self, $class;
}

# Calculate CRC 16 bit on block data
sub crc16 {
	my $self = $_[0];
	return new Digest::CRC(width => 16, poly => 0x1021)->add($self->{data})->digest;
}

# Return data one char at a time
sub data {
	my $self = $_[0];
	return wantarray
		? split(//, $self->{data})
		: substr($self->{data}, 0, $self->{'length'})
}

sub number {
	my $self = $_[0];
	return $self->{number};
}

# Stringify block for transfer
sub to_string {
	my $self = $_[0];
	my $block_num = $self->number();

	# Assemble block to be transferred
	my $xfer = pack(

		'CCCA128n',
  
		Device::SerialPort::Xmodem::Constants::soh,

		$block_num,                    # Block number

		$block_num ^ 0xFF,             # 2's complement of block number

		scalar $self->data,            # Data chars

		$self->crc16()                 # Final crc16
	);

	return $xfer;
}

# ----------------------------------------------------------------

package Device::SerialPort::Xmodem::Buffer;

sub new {
	my($proto, $num, $data) = @_;
	my $class = ref $proto || $proto;

	# Define structure of a Xmodem transfer buffer
	my $self = [];
	bless($self);
	return $self;
}

# Push, pop, operations on buffer
sub push {
	my $self  = $_[0];
	my $block = $_[1];
	push @$self, $block;
}

sub pop {
	my $self = $_[0];
	pop @$self
}

# Get last block on buffer (to retransmit / re-receive)
sub last {
	my $self = $_[0];
	return $self->[ $#$self ];
}

sub blocks {
	return @{$_[0]};
}

#
# Replace n-block with given block object
#
sub replace {
	my $self  = $_[0];
	my $num   = $_[1];
	my $block = $_[2];

	$self->[$num] = $block;
}

sub dump {
	my $self = $_[0];
	my $output;

	# Join all blocks into string
	for (my $pos = 0; $pos < scalar($self->blocks()); $pos++) {
		$output .= $self->[$pos]->data();
	}

	# Clean out any end of file markers (^Z) in data
	$output =~ s/\x1A*$//;

	return $output;
}

# ----------------------------------------------------------------

package Device::SerialPort::Xmodem::Send;

use Fcntl qw(:DEFAULT :flock);

# Define default timeouts for CRC handshaking stage and checksum normal procedure
sub TIMEOUT_CRC      () {  3 };
sub TIMEOUT_CHECKSUM () { 10 };

our $TIMEOUT = TIMEOUT_CRC;
our $DEBUG   = 0;

sub new {
	my $proto = shift;
	my %opt   = @_;
	my $class = ref $proto || $proto;

	# If port does not exist fail
	_log('port = ', $opt{port});
	if( ! exists $opt{port} ) {
		_log('No valid port given, giving up.');
		return 0;
	}

	my $self = {
		_port    => $opt{port},
		_filename => $opt{filename},
		current_block => 0,
		timeouts  => 0,
	};

	bless $self, $class;
}

sub start {
	my $self  = $_[0];
	my $port = $self->{_port};
	my $file  = $_[1] || $self->{_filename};

	print "XModem: Start, waiting for handshake\n";

	_log('[start] checking modem[', $port, '] or file[', $file, '] members');
	return 0 unless $port and $file;

	# Initialize transfer
	$self->{current_block} = 0;
	$self->{timeouts}      = 0;
	$self->{aborted}       = 0;
	$self->{complete}      = 0;

	# Initialize a receiving buffer
	_log('[start] creating new receive buffer');

	my $buffer = Device::SerialPort::Xmodem::Buffer->new();

	$self->{current_block} = Device::SerialPort::Xmodem::Block->new(0);

	# Attempt to handshake
	return -1 unless $self->handshake();

	# Open input file
	my $fstatus_open = open(INFILE, '<' . $file);

	# If file does not open die gracefully
	if (!$fstatus_open) {
		_log('Error: cannot open file for reading, aborting transfer.\n');
		$self->abort_transfer();
		return -2;
	}
  
	# Get file lock
	my $fstatus_lock = flock(INFILE, LOCK_SH);
	
	# If file does not lock complain but carry on
	if (!$fstatus_lock) {
		_log('Warning: file could not be locked, proceeding anyhow.\n');
	}

	$| = 1;
	print "XModem: Sending: ";

	# Create first block
	my $block_data = undef;
	seek(INFILE, 0, 0);
	read(INFILE, $block_data, 128, 0);
	_log('[start] creating first data block [', unpack('H*',$block_data), '] data');
	$self->{current_block} = Device::SerialPort::Xmodem::Block->new(0x01, $block_data);

	# Main send cycle (subsequent timeout cycles)
	do {
    
		_log('doing loop\n');
	    
		$self->send_message($self->{current_block}->to_string());
	    
		my %message = $self->receive_message();
	    
		if ( $message{type} eq Device::SerialPort::Xmodem::Constants::ack() ) {
			# Received Ack, if more file remains send more
			print ".";
			_log('[start] received <ack>: ', $message{type}, ', sending preparing next block.\n');
			_log('building new block at ', ($self->{current_block}->number() * 128), ', 128 long.\n');
			seek(INFILE, ($self->{current_block}->number() * 128), 0);
			my $block_data = undef;
			my $bytes_read = read(INFILE, $block_data, 128, 0);
			if ($bytes_read != 0) {
				# Not EOT create next block
				_log('blocks read: ', $bytes_read, ', total length: ', length($block_data), '.\n');
				while (length($block_data) < 128) {
					_log('padding block_data');
					$block_data .= chr(0x1a);
				}
				_log('blocks read: ', $bytes_read, ', total length: ', length($block_data), '.\n');
				_log('[start] creating new data block [', unpack('H*',$block_data), '] data');
				_log('creating as block no ', ($self->{current_block}->number() + 1), '.\n');
				$self->{current_block} = Device::SerialPort::Xmodem::Block->new( ($self->{current_block}->number() + 1), $block_data);
				$self->{timeouts} = 0;
			} else {
				# Send EOT, we've hit the end!
				$self->send_eot();
				$self->{complete} = 1;
			}
		} else {
			# If last block transmitted mark complete and write file
			print "!";
			_log('[start] <nak> or assumed (garble): ', $message{type}, ', trying again.\n');
			my ($count_in, $string_in) = $self->port->read(255); print "BUFFER: $count_in: $string_in \n";
			$self->{timeouts}++;
		}
    
	} until (($self->{complete}) || ($self->timeouts() >= 10) || ($self->{aborted}));

	print "\n";
	$| = 0;

	if ($self->{complete}) {
		do {
			my %message = $self->receive_message();
			if ( $message{type} eq Device::SerialPort::Xmodem::Constants::ack() ) {
				return 1;
			} else {
        			$self->{timeouts}++;
      			}
    		} until ($self->timeouts() >= 10);
	}
  
	if ($self->timeouts() >= 10) {
		_log('Too many errors, giving up.\n');
		$self->abort_transfer();
		return -3;
	}

	return -255;
}

sub receive_message {
	my $self = $_[0];
	my $message_type;
  my $count_in = 0;
  my $received;
  my $done = 0;
  my $error = 0;
  
  my $receive_start_time = time;
	# Receive answer
  do {
    my $count_in_tmp = 0;
    my $received_tmp;
    ($count_in_tmp, $received_tmp) = $self->port->read(1);
    $received .= $received_tmp;
    $count_in += $count_in_tmp;
    if ($count_in > 0) {
      # short message, this is all the sender should receive
      $done = 1;
    } elsif (time > $receive_start_time + 2) {
      # wait for timeout, give the message at least a second
      $error = 1;
    }
  } while(!$done && !$error);
  
  if ($error) {
    _log('timeout receiving message');
  }
  
	_log('[receive_message][', $count_in, '] received [', unpack('H*',$received), '] data');

  # Get Message Type
  $message_type = ord(substr($received, 0, 1));
  
  my %message = (
    type => $message_type, # Message Type
  );
  
	return %message;
}

sub handshake {
	my $self = $_[0];
	my $count_in = 0;
	my $received;
	my $done = 0;
	my $error = 0;
	
	my $receive_start_time = time;
	# Receive answer
	do {
		my $count_in_tmp = 0;
		my $received_tmp;
		($count_in_tmp, $received_tmp) = $self->port->read(1);
		$received .= $received_tmp;
		$count_in += $count_in_tmp;
		if ($count_in > 0) {
			# short message, this is all the sender should receive
			$done = 1;
		} elsif (time > $receive_start_time + 11) {
			# wait for timeout, give the message at least ten seconds
			$error = 1;
		}
	} while(!$done && !$error);
	
	if ($error) {
		_log('timeout waiting for handshake');
		print "XModem: Handshake timeout\n";
		return 0;
	}
	
	_log('[handshake][', $count_in, '] received [', unpack('H*',$received), '] data');
	
	# Get Message Type
	if (ord(substr($received, 0, 1)) eq Device::SerialPort::Xmodem::Constants::C()) {
		print "XModem: Handshake success\n";
		return 1;
	} else {
		print "XModem: Handshake failure\n";
		return 0;
	}
}

sub send_message {
	# This function sends a raw data message to the open port.
	my $self = $_[0];
	my $message = $_[1];
	_log('[send_message] received [', unpack('H*',$message), '] data');
	$self->port->write($message);
	$self->port->write_drain();
	return 1;
}

sub send_eot {
	# Send EOT character
	my $self = $_[0];
	_log('sending <EOT>');
	$self->port->write( chr(Device::SerialPort::Xmodem::Constants::eot()) );
	$self->port->write_drain();
	return 1;
}

sub abort_transfer {
	# Send a cancel char to abort transfer
	my $self = $_[0];
	_log('aborting transfer');
	$self->port->write( chr(Device::SerialPort::Xmodem::Constants::can()) );
	$self->port->write_drain();
	$self->{aborted} = 1;
	return 1;
}

sub timeouts {
	my $self = $_[0];
	$self->{timeouts};
}

# Get `port' Device::SerialPort member
sub port {
	$_[0]->{_port};
}

sub _log {
	print STDERR @_, "\n" if $DEBUG
}

1;
__END__

=head1 NAME

Device::SerialPort::Xmodem - Xmodem file transfer protocol for Device::SerialPort

=head1 SYNOPSIS

  use Device::SerialPort::Xmodem;

=head1 DESCRIPTION

This is an Xmodem implementation designed to receive a file using 128
byte blocks. This module is intended to be passed an open and prepared
port with active connection.

At this time it can only receive 128 byte blocks, however 1k blocks are
in the works. I do plan to write a send functionality soon.

=head1 Device::SerialPort::Xmodem::Constants

=head2 Synopsis

This is a set of contants that return hex values for the following:

 nul     ^@    0x00    null
 soh     ^A    0x01    start of header 128 byte block
 stx     ^B    0x02    start of header 1k byte block
 eot     ^D    0x04    end of trasmission
 ack     ^E    0x06    acknowlegded
 nak     ^U    0x15    not acknowledged
 can     ^X    0x18    cancel
 C             0x43    C ASCII char
 ctrl_z  ^Z    0x1A    end of file marker

 
=head1 Xmodem::Block

Class that represents a single Xmodem data block.

=head2 Synopsis

	my $b = Xmodem::Block->new( 1, 'My Data...<until-128-chars>...' );

	# Calculate crc16
	$crc16 = $b->crc16();
  
  $b->to_string(); # outputs a formated message block

=head1 Xmodem::Buffer

Class that implements an Xmodem receive buffer of data blocks. Every block of data
is represented by a Device::SerialPort::Xmodem::Block object.

Blocks can be pushed and popped from the buffer. You can retrieve the last
block, or the list of blocks from buffer.

=head2 Synopsis

	my $buf = Xmodem::Buffer->new();
	my $b1  = Xmodem::Block->new(1, 'Data...');

	$buf->push($b1);

	my $b2  = Xmodem::Block->new(2, 'More data...');
	$buf->push($b2);

	my $last_block = $buf->last();

	print 'now I have ', scalar($buf->blocks()), ' in the buffer';
  
  print OUTFILE $buf->dump(); # outputs all data of all blocks in order

=head1 Device::SerialPort::Xmodem::Send

Control class to initiate and complete a X-modem file transfer in receive mode.

=head2 Synopsis

	my $send = Device::SerialPort::Xmodem::Send->new(
 		port     => {Device::SerialPort object},
		filename => 'name of file'
	);

	$send->start();

=head2 Object methods

=over 4

=item new()

Creates a new Device::SerialPort::Xmodem::Send object.

=item start()

Starts a new transfer until file send is complete. The only parameter accepted
is the local filename to be written. This quits if ten timeouts are received per block. 

=item receive_message()

Retreives a message, being an Xmodem command type (such as ack, nak, etc).

=item handshake()

If a <nak> message is received within 10 seconds returns true. 

=item send_message()

Sends a raw data message. This is typically a message block <soh> created by the
block to_string() function.

=item send_eot()

Sends a <eot> char, this signals to receiver that the file transfer is complete.

=item abort_transfer()

Sends a cancel <can> char, that signals to receiver that transfer is aborted.

=item timeouts()

Returns the number of timeouts that have occured, typically this is per message block.

=item port()

Returns the underlying L<Device::Serial> object.

=back

=head1 SEE ALSO

Device::SerialPort

Device::Modem::Protocol::Xmodem

=head1 AUTHORS

 Based on Device::Modem::Protocol::Xmodem, version 1.44, by Cosimo Streppone, E<lt>cosimo@cpan.orgE<gt>.
 Ported to Device::SerialPort by Aaron Mitti, E<lt>mitti@cpan.orgE<gt>. 

=head1 COPYRIGHT AND LICENCE

 Copyright (C) 2002-2004 Cosimo Streppone, E<lt>cosimo@cpan.orgE<gt>
 Copyright (C) 2005 by Aaron Mitti, E<lt>mitti@cpan.orgE<gt> 

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


=cut

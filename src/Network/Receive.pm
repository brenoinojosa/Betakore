#########################################################################
#  OpenKore - Server message parsing
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#########################################################################
##
# MODULE DESCRIPTION: Server message parsing
#
# This class is responsible for parsing messages that are sent by the RO
# server to Kore. Information in the messages are stored in global variables
# (in the module Globals).
#
# Please also read <a href="http://wiki.openkore.com/index.php/Network_subsystem">the
# network subsystem overview.</a>
package Network::Receive;

use strict;
use Time::HiRes qw(time);
use Network::PacketParser; # import
use base qw(Network::PacketParser);
use encoding 'utf8';
use Carp::Assert;
use Scalar::Util;
use Socket qw(inet_aton inet_ntoa);

use AI;
use Globals;
#use Settings;
use Log qw(message warning error debug);
use FileParsers qw(updateMonsterLUT updateNPCLUT updateItemsSellTable);
use I18N qw(bytesToString stringToBytes);
use Interface;
use Network;
use Network::MessageTokenizer;
use Misc;
use Plugins;
use Utils;
use Utils::Exceptions;
use Utils::Crypton;
use Translation;

# object_type constants for &actor_display
use constant {
	PC_TYPE => 0x0,
	NPC_TYPE => 0x1,
	ITEM_TYPE => 0x2,
	SKILL_TYPE => 0x3,
	UNKNOWN_TYPE => 0x4,
	NPC_MOB_TYPE => 0x5,
	NPC_EVT_TYPE => 0x6,
	NPC_PET_TYPE => 0x7,
	NPC_HO_TYPE => 0x8,
	NPC_MERSOL_TYPE => 0x9,
	NPC_ELEMENTAL_TYPE => 0xa
};

use constant {
	REFUSE_INVALID_ID => 0x0,
	REFUSE_INVALID_PASSWD => 0x1,
	REFUSE_ID_EXPIRED => 0x2,
	ACCEPT_ID_PASSWD => 0x3,
	REFUSE_NOT_CONFIRMED => 0x4,
	REFUSE_INVALID_VERSION => 0x5,
	REFUSE_BLOCK_TEMPORARY => 0x6,
	REFUSE_BILLING_NOT_READY => 0x7,
	REFUSE_NONSAKRAY_ID_BLOCKED => 0x8,
	REFUSE_BAN_BY_DBA => 0x9,
	REFUSE_EMAIL_NOT_CONFIRMED => 0xa,
	REFUSE_BAN_BY_GM => 0xb,
	REFUSE_TEMP_BAN_FOR_DBWORK => 0xc,
	REFUSE_SELF_LOCK => 0xd,
	REFUSE_NOT_PERMITTED_GROUP => 0xe,
	REFUSE_WAIT_FOR_SAKRAY_ACTIVE => 0xf,
	REFUSE_NOT_CHANGED_PASSWD => 0x10,
	REFUSE_BLOCK_INVALID => 0x11,
	REFUSE_WARNING => 0x12,
	REFUSE_NOT_OTP_USER_INFO => 0x13,
	REFUSE_OTP_AUTH_FAILED => 0x14,
	REFUSE_SSO_AUTH_FAILED => 0x15,
	REFUSE_NOT_ALLOWED_IP_ON_TESTING => 0x16,
	REFUSE_OVER_BANDWIDTH => 0x17,
	REFUSE_OVER_USERLIMIT => 0x18,
	REFUSE_UNDER_RESTRICTION => 0x19,
	REFUSE_BY_OUTER_SERVER => 0x1a,
	REFUSE_BY_UNIQUESERVER_CONNECTION => 0x1b,
	REFUSE_BY_AUTHSERVER_CONNECTION => 0x1c,
	REFUSE_BY_BILLSERVER_CONNECTION => 0x1d,
	REFUSE_BY_AUTH_WAITING => 0x1e,
	REFUSE_DELETED_ACCOUNT => 0x63,
	REFUSE_ALREADY_CONNECT => 0x64,
	REFUSE_TEMP_BAN_HACKING_INVESTIGATION => 0x65,
	REFUSE_TEMP_BAN_BUG_INVESTIGATION => 0x66,
	REFUSE_TEMP_BAN_DELETING_CHAR => 0x67,
	REFUSE_TEMP_BAN_DELETING_SPOUSE_CHAR => 0x68,
	REFUSE_USER_PHONE_BLOCK => 0x69,
	ACCEPT_LOGIN_USER_PHONE_BLOCK => 0x6a,
	ACCEPT_LOGIN_CHILD => 0x6b,
	REFUSE_IS_NOT_FREEUSER => 0x6c,
	REFUSE_INVALID_ONETIMELIMIT => 0x6d,
	REFUSE_CHANGE_PASSWD_FORCE => 0x6e,
	REFUSE_OUTOFDATE_PASSWORD => 0x6f,
	REFUSE_NOT_CHANGE_ACCOUNTID => 0xf0,
	REFUSE_NOT_CHANGE_CHARACTERID => 0xf1,
	REFUSE_SSO_AUTH_BLOCK_USER => 0x1394,
	REFUSE_SSO_AUTH_GAME_APPLY => 0x1395,
	REFUSE_SSO_AUTH_INVALID_GAMENUM => 0x1396,
	REFUSE_SSO_AUTH_INVALID_USER => 0x1397,
	REFUSE_SSO_AUTH_OTHERS => 0x1398,
	REFUSE_SSO_AUTH_INVALID_AGE => 0x1399,
	REFUSE_SSO_AUTH_INVALID_MACADDRESS => 0x139a,
	REFUSE_SSO_AUTH_BLOCK_ETERNAL => 0x13c6,
	REFUSE_SSO_AUTH_BLOCK_ACCOUNT_STEAL => 0x13c7,
	REFUSE_SSO_AUTH_BLOCK_BUG_INVESTIGATION => 0x13c8,
	REFUSE_SSO_NOT_PAY_USER => 0x13ba,
	REFUSE_SSO_ALREADY_LOGIN_USER => 0x13bb,
	REFUSE_SSO_CURRENT_USED_USER => 0x13bc,
	REFUSE_SSO_OTHER_1 => 0x13bd,
	REFUSE_SSO_DROP_USER => 0x13be,
	REFUSE_SSO_NOTHING_USER => 0x13bf,
	REFUSE_SSO_OTHER_2 => 0x13c0,
	REFUSE_SSO_WRONG_RATETYPE_1 => 0x13c1,
	REFUSE_SSO_EXTENSION_PCBANG_TIME => 0x13c2,
	REFUSE_SSO_WRONG_RATETYPE_2 => 0x13c3,
};

######################################
### CATEGORY: Class methods
######################################

# Just a wrapper for SUPER::parse.
sub parse {
	my $self = shift;
	my $args = $self->SUPER::parse(@_);

	if ($args && $config{debugPacket_received} == 3 &&
			existsInList($config{'debugPacket_include'}, $args->{switch})) {
		my $packet = $self->{packet_list}{$args->{switch}};
		my ($name, $packString, $varNames) = @{$packet};

		my @vars = ();
		for my $varName (@{$varNames}) {
			message "$varName = $args->{$varName}\n";
		}
	}

	return $args;
}

##
# Network::Receive->decrypt(r_msg, themsg)
# r_msg: a reference to a scalar.
# themsg: the message to decrypt.
#
# Decrypts the packets in $themsg and put the result in the scalar
# referenced by $r_msg.
#
# This is an old method used back in the iRO beta 2 days when iRO had encrypted packets.
# At the moment (December 20 2006) there are no servers that still use encrypted packets.
#
# Example:
# } elsif ($switch eq "ABCD") {
# 	my $level;
# 	Network::Receive->decrypt(\$level, substr($msg, 0, 2));
sub decrypt {
	use bytes;
	my ($self, $r_msg, $themsg) = @_;
	my @mask;
	my $i;
	my ($temp, $msg_temp, $len_add, $len_total, $loopin, $len, $val);
	if ($config{encrypt} == 1) {
		undef $$r_msg;
		undef $len_add;
		undef $msg_temp;
		for ($i = 0; $i < 13;$i++) {
			$mask[$i] = 0;
		}
		$len = unpack("v1",substr($themsg,0,2));
		$val = unpack("v1",substr($themsg,2,2));
		{
			use integer;
			$temp = ($val * $val * 1391);
		}
		$temp = ~(~($temp));
		$temp = $temp % 13;
		$mask[$temp] = 1;
		{
			use integer;
			$temp = $val * 1397;
		}
		$temp = ~(~($temp));
		$temp = $temp % 13;
		$mask[$temp] = 1;
		for($loopin = 0; ($loopin + 4) < $len; $loopin++) {
 			if (!($mask[$loopin % 13])) {
  				$msg_temp .= substr($themsg,$loopin + 4,1);
			}
		}
		if (($len - 4) % 8 != 0) {
			$len_add = 8 - (($len - 4) % 8);
		}
		$len_total = $len + $len_add;
		$$r_msg = $msg_temp.substr($themsg, $len_total, length($themsg) - $len_total);
	} elsif ($config{encrypt} >= 2) {
		undef $$r_msg;
		undef $len_add;
		undef $msg_temp;
		for ($i = 0; $i < 17;$i++) {
			$mask[$i] = 0;
		}
		$len = unpack("v1",substr($themsg,0,2));
		$val = unpack("v1",substr($themsg,2,2));
		{
			use integer;
			$temp = ($val * $val * 34953);
		}
		$temp = ~(~($temp));
		$temp = $temp % 17;
		$mask[$temp] = 1;
		{
			use integer;
			$temp = $val * 2341;
		}
		$temp = ~(~($temp));
		$temp = $temp % 17;
		$mask[$temp] = 1;
		for($loopin = 0; ($loopin + 4) < $len; $loopin++) {
 			if (!($mask[$loopin % 17])) {
  				$msg_temp .= substr($themsg,$loopin + 4,1);
			}
		}
		if (($len - 4) % 8 != 0) {
			$len_add = 8 - (($len - 4) % 8);
		}
		$len_total = $len + $len_add;
		$$r_msg = $msg_temp.substr($themsg, $len_total, length($themsg) - $len_total);
	} else {
		$$r_msg = $themsg;
	}
}


#######################################
### CATEGORY: Private class methods
#######################################

##
# int Network::Receive::queryLoginPinCode([String message])
# Returns: login PIN code, or undef if cancelled
# Ensures: length(result) in 4..8
#
# Request login PIN code from user.
sub queryLoginPinCode {
	my $message = $_[0] || T("You've never set a login PIN code before.\nPlease enter a new login PIN code:");
	do {
		my $input = $interface->query($message, isPassword => 1,);
		if (!defined($input)) {
			quit();
			return;
		} else {
			if ($input !~ /^\d+$/) {
				$interface->errorDialog(T("The PIN code may only contain digits."));
			} elsif ((length($input) <= 3) || (length($input) >= 9)) {
				$interface->errorDialog(T("The PIN code must be between 4 and 9 characters."));
			} else {
				return $input;
			}
		}
	} while (1);
}

##
# boolean Network::Receive->queryAndSaveLoginPinCode([String message])
# Returns: true on success
#
# Request login PIN code from user and save it in config.
sub queryAndSaveLoginPinCode {
	my ($self, $message) = @_;
	my $pin = queryLoginPinCode($message);
	if (defined $pin) {
		configModify('loginPinCode', $pin, silent => 1);
		return 1;
	} else {
		return 0;
	}
}

sub changeToInGameState {
	if ($net->version() == 1) {
		if ($accountID && UNIVERSAL::isa($char, 'Actor::You')) {
			if ($net->getState() != Network::IN_GAME) {
				$net->setState(Network::IN_GAME);
			}
			return 1;
		} else {
			if ($net->getState() != Network::IN_GAME_BUT_UNINITIALIZED) {
				$net->setState(Network::IN_GAME_BUT_UNINITIALIZED);
				if ($config{verbose} && $messageSender && !$sentWelcomeMessage) {
					$messageSender->injectAdminMessage("Please relogin to enable X-${Settings::NAME}.");
					$sentWelcomeMessage = 1;
				}
			}
			return 0;
		}
	} else {
		return 1;
	}
}

### Packet inner struct handlers

# The block size in the received_characters packet varies from server to server.
# This method may be overrided in other ServerType handlers to return
# the correct block size.
sub received_characters_blockSize {
	if ($masterServer && $masterServer->{charBlockSize}) {
		return $masterServer->{charBlockSize};
	} else {
		return 106;
	}
}

# The length must exactly match charBlockSize, as it's used to construct packets.
sub received_characters_unpackString {
	for ($masterServer && $masterServer->{charBlockSize}) {
		# unknown purpose (0 = disabled, otherwise displays "Add-Ons" sidebar) (from rA)
		return 'a4 V9 v V2 v14 Z24 C8 v Z16 V x4 x4 x4' if $_ == 144;
		# change slot feature
		return 'a4 V9 v V2 v14 Z24 C8 v Z16 V x4 x4' if $_ == 140;
		# robe
		return 'a4 V9 v V2 v14 Z24 C8 v Z16 V x4' if $_ == 136;
		# delete date
		return 'a4 V9 v V2 v14 Z24 C8 v Z16 V' if $_ == 132;
		return 'a4 V9 v V2 v14 Z24 C8 v Z16' if $_ == 128;
		# bRO (bitfrost update)
		return 'a4 V9 v V2 v14 Z24 C8 v Z12' if $_ == 124;
		return 'a4 V9 v V2 v14 Z24 C6 v2 x4' if $_ == 116; # TODO: (missing 2 last bytes)
		return 'a4 V9 v V2 v14 Z24 C6 v2' if $_ == 112;
		return 'a4 V9 v17 Z24 C6 v2' if $_ == 108;
		return 'a4 V9 v17 Z24 C6 v' if $_ == 106 || !$_;
		die "Unknown charBlockSize: $_";
	}
}

### Parse/reconstruct callbacks and packet handlers

sub parse_account_server_info {
	my ($self, $args) = @_;

	if (length $args->{lastLoginIP} == 4 && $args->{lastLoginIP} ne "\0"x4) {
		$args->{lastLoginIP} = inet_ntoa($args->{lastLoginIP});
	} else {
		delete $args->{lastLoginIP};
	}

	@{$args->{servers}} = map {
		my %server;
		@server{qw(ip port name users display)} = unpack 'a4 v Z20 v2 x2', $_;
		if ($masterServer && $masterServer->{private}) {
			$server{ip} = $masterServer->{ip};
		} else {
			$server{ip} = inet_ntoa($server{ip});
		}
		$server{name} = bytesToString($server{name});
		\%server
	} unpack '(a32)*', $args->{serverInfo};
}

sub reconstruct_account_server_info {
	my ($self, $args) = @_;

	$args->{lastLoginIP} = inet_aton($args->{lastLoginIP});

	$args->{serverInfo} = pack '(a32)*', map { pack(
		'a4 v Z20 v2 x2',
		inet_aton($_->{ip}),
		$_->{port},
		stringToBytes($_->{name}),
		@{$_}{qw(users display)},
	) } @{$args->{servers}};
}

sub account_server_info {
	my ($self, $args) = @_;

	$net->setState(2);
	undef $conState_tries;
	$sessionID = $args->{sessionID};
	$accountID = $args->{accountID};
	$sessionID2 = $args->{sessionID2};
	# Account sex should only be 0 (female) or 1 (male)
	# inRO gives female as 2 but expects 0 back
	# do modulus of 2 here to fix?
	# FIXME: we should check exactly what operation the client does to the number given
	$accountSex = $args->{accountSex} % 2;
	$accountSex2 = ($config{'sex'} ne "") ? $config{'sex'} : $accountSex;

	# any servers with lastLoginIP lastLoginTime?
	# message TF("Last login: %s from %s\n", @{$args}{qw(lastLoginTime lastLoginIP)}) if ...;

	message swrite(
		T("-----------Account Info------------\n" .
		"Account ID: \@<<<<<<<<< \@<<<<<<<<<<\n" .
		"Sex:        \@<<<<<<<<<<<<<<<<<<<<<\n" .
		"Session ID: \@<<<<<<<<< \@<<<<<<<<<<\n" .
		"            \@<<<<<<<<< \@<<<<<<<<<<\n" .
		"-----------------------------------"),
		[unpack('V',$accountID), getHex($accountID), $sex_lut{$accountSex}, unpack('V',$sessionID), getHex($sessionID),
		unpack('V',$sessionID2), getHex($sessionID2)]), 'connection';

	@servers = @{$args->{servers}};

	message T("---------------------- Servers -----------------------\n" .
			"#   Name                  Users  IP              Port\n"), 'connection';
	for (my $num = 0; $num < @servers; $num++) {
		message(swrite(
			"@<< @<<<<<<<<<<<<<<<<<<<< @<<<<< @<<<<<<<<<<<<<< @<<<<<",
			[$num, $servers[$num]{name}, $servers[$num]{users}, $servers[$num]{ip}, $servers[$num]{port}]
		), 'connection');
	}
	message("------------------------------------------------------\n", 'connection');

	if ($net->version != 1) {
		message T("Closing connection to Account Server\n"), 'connection';
		$net->serverDisconnect();
		if (!$masterServer->{charServer_ip} && $config{server} eq "") {
			my @serverList;
			foreach my $server (@servers) {
				push @serverList, $server->{name};
			}
			my $ret = $interface->showMenu(
					T("Please select your login server."),
					\@serverList,
					title => T("Select Login Server"));
			if ($ret == -1) {
				quit();
			} else {
				main::configModify('server', $ret, 1);
			}

		} elsif ($masterServer->{charServer_ip}) {
			message TF("Forcing connect to char server %s: %s\n", $masterServer->{charServer_ip}, $masterServer->{charServer_port}), 'connection';

		} else {
			message TF("Selected server: %s\n", @servers[$config{server}]->{name}), 'connection';
		}
	}

	# FIXME better support for multiple received_characters packets
	undef @chars;
	if ($config{'XKore'} eq '1') {
		$incomingMessages->nextMessageMightBeAccountID();
	}
}

sub connection_refused {
	my ($self, $args) = @_;

	error TF("The server has denied your connection (error: %d).\n", $args->{error}), 'connection';
}

*actor_exists = *actor_display_compatibility;
*actor_connected = *actor_display_compatibility;
*actor_moved = *actor_display_compatibility;
*actor_spawned = *actor_display_compatibility;
sub actor_display_compatibility {
	my ($self, $args) = @_;
	# compatibility; TODO do it in PacketParser->parse?
	Plugins::callHook('packet_pre/actor_display', $args);
	&actor_display unless $args->{return};
	Plugins::callHook('packet/actor_display', $args);
}

# This function is a merge of actor_exists, actor_connected, actor_moved, etc...
sub actor_display {
	my ($self, $args) = @_;
	return unless changeToInGameState();
	my ($actor, $mustAdd);


	#### Initialize ####

	my $nameID = unpack("V", $args->{ID});

	if ($args->{switch} eq "0086") {
		# Message 0086 contains less information about the actor than other similar
		# messages. So we use the existing actor information.
		my $coordsArg = $args->{coords};
		my $tickArg = $args->{tick};
		$args = Actor::get($args->{ID})->deepCopy();
		# Here we overwrite the $args data with the 0086 packet data.
		$args->{switch} = "0086";
		$args->{coords} = $coordsArg;
		$args->{tick} = $tickArg; # lol tickcount what do we do with that? debug "tick: " . $tickArg/1000/3600/24 . "\n";
	}

	my (%coordsFrom, %coordsTo);
	if (length $args->{coords} == 6) {
		# Actor Moved
		makeCoordsFromTo(\%coordsFrom, \%coordsTo, $args->{coords}); # body dir will be calculated using the vector
	} else {
		# Actor Spawned/Exists
		makeCoordsDir(\%coordsTo, $args->{coords}, \$args->{body_dir});
		%coordsFrom = %coordsTo;
	}

	# Remove actors that are located outside the map
	# This may be caused by:
	#  - server sending us false actors
	#  - actor packets not being parsed correctly
	if (defined $field && ($field->isOffMap($coordsFrom{x}, $coordsFrom{y}) || $field->isOffMap($coordsTo{x}, $coordsTo{y}))) {
		warning TF("Removed actor with off map coordinates: (%d,%d)->(%d,%d), field max: (%d,%d)\n",$coordsFrom{x},$coordsFrom{y},$coordsTo{x},$coordsTo{y},$field->width(),$field->height());
		return;
	}

	# Remove actors with a distance greater than removeActorWithDistance. Useful for vending (so you don't spam
	# too many packets in prontera and cause server lag). As a side effect, you won't be able to "see" actors
	# beyond removeActorWithDistance.
	if ($config{removeActorWithDistance}) {
		if ((my $block_dist = blockDistance($char->{pos_to}, \%coordsTo)) > ($config{removeActorWithDistance})) {
			my $nameIdTmp = unpack("V", $args->{ID});
			debug "Removed out of sight actor $nameIdTmp at ($coordsTo{x}, $coordsTo{y}) (distance: $block_dist)\n";
			return;
		}
	}
=pod
	# Zealotus bug
	if ($args->{type} == 1200) {
		open DUMP, ">> test_Zealotus.txt";
		print DUMP "Zealotus: " . $nameID . "\n";
		print DUMP Dumper($args);
		close DUMP;
	}
=cut

	#### Step 0: determine object type ####
	my $object_class;
	if (defined $args->{object_type}) {
		if ($args->{type} == 45) { # portals use the same object_type as NPCs
			$object_class = 'Actor::Portal';
		} else {
			$object_class = {
				PC_TYPE, 'Actor::Player',
				# NPC_TYPE? # not encountered, NPCs are NPC_EVT_TYPE
				# SKILL_TYPE? # not encountered
				# UNKNOWN_TYPE? # not encountered
				NPC_MOB_TYPE, 'Actor::Monster',
				NPC_EVT_TYPE, 'Actor::NPC', # both NPCs and portals
				NPC_PET_TYPE, 'Actor::Pet',
				NPC_HO_TYPE, 'Actor::Slave',
				# NPC_MERSOL_TYPE? # not encountered
				# NPC_ELEMENTAL_TYPE? # not encountered
			}->{$args->{object_type}};
		}

	}

	unless (defined $object_class) {
		if ($jobs_lut{$args->{type}}) {
			unless ($args->{type} > 6000) {
				$object_class = 'Actor::Player';
			} else {
				$object_class = 'Actor::Slave';
			}
		} elsif ($args->{type} == 45) {
			$object_class = 'Actor::Portal';

		} elsif ($args->{type} >= 1000) {
			if ($args->{hair_style} == 0x64) {
				$object_class = 'Actor::Pet';
			} else {
				$object_class = 'Actor::Monster';
			}
		} else {   # ($args->{type} < 1000 && $args->{type} != 45 && !$jobs_lut{$args->{type}})
			$object_class = 'Actor::NPC';
		}
	}

	#### Step 1: create the actor object ####

	if ($object_class eq 'Actor::Player') {
		# Actor is a player
		$actor = $playersList->getByID($args->{ID});
		if (!defined $actor) {
			$actor = new Actor::Player();
			$actor->{appear_time} = time;
			# New actor_display packets include the player's name
			if ($args->{switch} eq "0086") {
				$actor->{name} = $args->{name};
			} else {
				$actor->{name} = bytesToString($args->{name}) if exists $args->{name};
			}
			$mustAdd = 1;
		}
		$actor->{nameID} = $nameID;
	} elsif ($object_class eq 'Actor::Slave') {
		# Actor is a homunculus or a mercenary
		$actor = $slavesList->getByID($args->{ID});
		if (!defined $actor) {
			$actor = ($char->{slaves} && $char->{slaves}{$args->{ID}})
			? $char->{slaves}{$args->{ID}} : new Actor::Slave ($args->{type});

			$actor->{appear_time} = time;
			$actor->{name_given} = bytesToString($args->{name}) if exists $args->{name};
			$actor->{jobId} = $args->{type} if exists $args->{type};
			$mustAdd = 1;
		}
		$actor->{nameID} = $nameID;
	} elsif ($object_class eq 'Actor::Portal') {
		# Actor is a portal
		$actor = $portalsList->getByID($args->{ID});
		if (!defined $actor) {
			$actor = new Actor::Portal();
			$actor->{appear_time} = time;
			my $exists = portalExists($field->baseName, \%coordsTo);
			$actor->{source}{map} = $field->baseName;
			if ($exists ne "") {
				$actor->setName("$portals_lut{$exists}{source}{map} -> " . getPortalDestName($exists));
			}
			$mustAdd = 1;

			# Strangely enough, portals (like all other actors) have names, too.
			# We _could_ send a "actor_info_request" packet to find the names of each portal,
			# however I see no gain from this. (And it might even provide another way of private
			# servers to auto-ban bots.)
		}
		$actor->{nameID} = $nameID;
	} elsif ($object_class eq 'Actor::Pet') {
		# Actor is a pet
		$actor = $petsList->getByID($args->{ID});
		if (!defined $actor) {
			$actor = new Actor::Pet();
			$actor->{appear_time} = time;
			if ($monsters_lut{$args->{type}}) {
				$actor->setName($monsters_lut{$args->{type}});
			}
			$actor->{name_given} = exists $args->{name} ? bytesToString($args->{name}) : "Unknown";
			$mustAdd = 1;

			# Previously identified monsters could suddenly be identified as pets.
			if ($monstersList->getByID($args->{ID})) {
				$monstersList->removeByID($args->{ID});
			}

			# Why do monsters and pets use nameID as type?
			$actor->{nameID} = $args->{type};

		}
	} elsif ($object_class eq 'Actor::Monster') {
		$actor = $monstersList->getByID($args->{ID});
		if (!defined $actor) {
			$actor = new Actor::Monster();
			$actor->{appear_time} = time;
			if ($monsters_lut{$args->{type}}) {
				$actor->setName($monsters_lut{$args->{type}});
			}
			#$actor->{name_given} = exists $args->{name} ? bytesToString($args->{name}) : "Unknown";
			$actor->{name_given} = "Unknown";
			$actor->{binType} = $args->{type};
			$mustAdd = 1;

			# Why do monsters and pets use nameID as type?
			$actor->{nameID} = $args->{type};
		}
	} elsif ($object_class eq 'Actor::NPC') {
		# Actor is an NPC
		$actor = $npcsList->getByID($args->{ID});
		if (!defined $actor) {
			$actor = new Actor::NPC();
			$actor->{appear_time} = time;
			$actor->{name} = bytesToString($args->{name}) if exists $args->{name};
			$mustAdd = 1;
		}
		$actor->{nameID} = $nameID;
	}

	#### Step 2: update actor information ####
	$actor->{ID} = $args->{ID};
	$actor->{jobID} = $args->{type};
	$actor->{type} = $args->{type};
	$actor->{lv} = $args->{lv};
	$actor->{pos} = {%coordsFrom};
	$actor->{pos_to} = {%coordsTo};
	$actor->{walk_speed} = $args->{walk_speed} / 1000 if (exists $args->{walk_speed} && $args->{switch} ne "0086");
	$actor->{time_move} = time;
	$actor->{time_move_calc} = distance(\%coordsFrom, \%coordsTo) * $actor->{walk_speed};
	# 0086 would need that?
	$actor->{object_type} = $args->{object_type} if (defined $args->{object_type});

	if (UNIVERSAL::isa($actor, "Actor::Player")) {
		# None of this stuff should matter if the actor isn't a player... => does matter for a guildflag npc!

		# Interesting note about emblemID. If it is 0 (or none), the Ragnarok
		# client will display "Send (Player) a guild invitation" (assuming one has
		# invitation priveledges), regardless of whether or not guildID is set.
		# I bet that this is yet another brilliant "feature" by GRAVITY's good programmers.
		$actor->{emblemID} = $args->{emblemID} if (exists $args->{emblemID});
		$actor->{guildID} = $args->{guildID} if (exists $args->{guildID});

		if (exists $args->{lowhead}) {
			$actor->{headgear}{low} = $args->{lowhead};
			$actor->{headgear}{mid} = $args->{midhead};
			$actor->{headgear}{top} = $args->{tophead};
			$actor->{weapon} = $args->{weapon};
			$actor->{shield} = $args->{shield};
		}

		$actor->{sex} = $args->{sex};

		if ($args->{act} == 1) {
			$actor->{dead} = 1;
		} elsif ($args->{act} == 2) {
			$actor->{sitting} = 1;
		}

		# Monsters don't have hair colors or heads to look around...
		$actor->{hair_color} = $args->{hair_color} if (exists $args->{hair_color});

	} elsif (UNIVERSAL::isa($actor, "Actor::NPC") && $args->{type} == 722) { # guild flag has emblem
		# odd fact: "this data can also be found in a strange place:
		# (shield OR lowhead) + midhead = emblemID		(either shield or lowhead depending on the packet)
		# tophead = guildID
		$actor->{emblemID} = $args->{emblemID};
		$actor->{guildID} = $args->{guildID};
	}

	# But hair_style is used for pets, and their bodies can look different ways...
	$actor->{hair_style} = $args->{hair_style} if (exists $args->{hair_style});
	$actor->{look}{body} = $args->{body_dir} if (exists $args->{body_dir});
	$actor->{look}{head} = $args->{head_dir} if (exists $args->{head_dir});

	# When stance is non-zero, character is bobbing as if they had just got hit,
	# but the cursor also turns to a sword when they are mouse-overed.
	#$actor->{stance} = $args->{stance} if (exists $args->{stance});

	# Visual effects are a set of flags (some of the packets don't have this argument)
	$actor->{opt3} = $args->{opt3} if (exists $args->{opt3}); # stackable

	# Known visual effects:
	# 0x0001 = Yellow tint (eg, a quicken skill)
	# 0x0002 = Red tint (eg, power-thrust)
	# 0x0004 = Gray tint (eg, energy coat)
	# 0x0008 = Slow lightning (eg, mental strength)
	# 0x0010 = Fast lightning (eg, MVP fury)
	# 0x0020 = Black non-moving statue (eg, stone curse)
	# 0x0040 = Translucent weapon
	# 0x0080 = Translucent red sprite (eg, marionette control?)
	# 0x0100 = Spaztastic weapon image (eg, mystical amplification)
	# 0x0200 = Gigantic glowy sphere-thing
	# 0x0400 = Translucent pink sprite (eg, marionette control?)
	# 0x0800 = Glowy sprite outline (eg, assumptio)
	# 0x1000 = Bright red sprite, slowly moving red lightning (eg, MVP fury?)
	# 0x2000 = Vortex-type effect

	# Note that these are flags, and you can mix and match them
	# Example: 0x000C (0x0008 & 0x0004) = gray tint with slow lightning

=pod
typedef enum <unnamed-tag> {
  SHOW_EFST_NORMAL =  0x0,
  SHOW_EFST_QUICKEN =  0x1,
  SHOW_EFST_OVERTHRUST =  0x2,
  SHOW_EFST_ENERGYCOAT =  0x4,
  SHOW_EFST_EXPLOSIONSPIRITS =  0x8,
  SHOW_EFST_STEELBODY =  0x10,
  SHOW_EFST_BLADESTOP =  0x20,
  SHOW_EFST_AURABLADE =  0x40,
  SHOW_EFST_REDBODY =  0x80,
  SHOW_EFST_LIGHTBLADE =  0x100,
  SHOW_EFST_MOON =  0x200,
  SHOW_EFST_PINKBODY =  0x400,
  SHOW_EFST_ASSUMPTIO =  0x800,
  SHOW_EFST_SUN_WARM =  0x1000,
  SHOW_EFST_REFLECT =  0x2000,
  SHOW_EFST_BUNSIN =  0x4000,
  SHOW_EFST_SOULLINK =  0x8000,
  SHOW_EFST_UNDEAD =  0x10000,
  SHOW_EFST_CONTRACT =  0x20000,
} <unnamed-tag>;
=cut

	# Save these parameters ...
	$actor->{opt1} = $args->{opt1}; # nonstackable
	$actor->{opt2} = $args->{opt2}; # stackable
	$actor->{option} = $args->{option}; # stackable

	# And use them to set status flags.
	if (setStatus($actor, $args->{opt1}, $args->{opt2}, $args->{option})) {
		$mustAdd = 0;
	}


	#### Step 3: Add actor to actor list ####
	if ($mustAdd) {
		if (UNIVERSAL::isa($actor, "Actor::Player")) {
			$playersList->add($actor);

		} elsif (UNIVERSAL::isa($actor, "Actor::Monster")) {
			$monstersList->add($actor);

		} elsif (UNIVERSAL::isa($actor, "Actor::Pet")) {
			$petsList->add($actor);

		} elsif (UNIVERSAL::isa($actor, "Actor::Portal")) {
			$portalsList->add($actor);

		} elsif (UNIVERSAL::isa($actor, "Actor::NPC")) {
			my $ID = $args->{ID};
			my $location = $field->baseName . " $actor->{pos}{x} $actor->{pos}{y}";
			if ($npcs_lut{$location}) {
				$actor->setName($npcs_lut{$location});
			}
			$npcsList->add($actor);

		} elsif (UNIVERSAL::isa($actor, "Actor::Slave")) {
			$slavesList->add($actor);
		}
	}


	#### Packet specific ####
	if ($args->{switch} eq "0078" ||
		$args->{switch} eq "01D8" ||
		$args->{switch} eq "022A" ||
		$args->{switch} eq "02EE" ||
		$args->{switch} eq "07F9" ||
		$args->{switch} eq "0857") {
		# Actor Exists (standing)

		if ($actor->isa('Actor::Player')) {
			my $domain = existsInList($config{friendlyAID}, unpack("V", $actor->{ID})) ? 'parseMsg_presence' : 'parseMsg_presence/player';
			debug "Player Exists: " . $actor->name . " ($actor->{binID}) Level $actor->{lv} $sex_lut{$actor->{sex}} $jobs_lut{$actor->{jobID}} ($coordsFrom{x}, $coordsFrom{y})\n", $domain;

			Plugins::callHook('player', {player => $actor});  #backwards compatibility

			Plugins::callHook('player_exist', {player => $actor});

		} elsif ($actor->isa('Actor::NPC')) {
			message TF("NPC Exists: %s (%d, %d) (ID %d) - (%d)\n", $actor->name, $actor->{pos_to}{x}, $actor->{pos_to}{y}, $actor->{nameID}, $actor->{binID}), "parseMsg_presence", 1;

		} elsif ($actor->isa('Actor::Portal')) {
			message TF("Portal Exists: %s (%s, %s) - (%s)\n", $actor->name, $actor->{pos_to}{x}, $actor->{pos_to}{y}, $actor->{binID}), "portals", 1;

		} elsif ($actor->isa('Actor::Monster')) {
			debug sprintf("Monster Exists: %s (%d)\n", $actor->name, $actor->{binID}), "parseMsg_presence", 1;

		} elsif ($actor->isa('Actor::Pet')) {
			debug sprintf("Pet Exists: %s (%d)\n", $actor->name, $actor->{binID}), "parseMsg_presence", 1;

		} elsif ($actor->isa('Actor::Slave')) {
			debug sprintf("Slave Exists: %s (%d)\n", $actor->name, $actor->{binID}), "parseMsg_presence", 1;

		} else {
			debug sprintf("Unknown Actor Exists: %s (%d)\n", $actor->name, $actor->{binID}), "parseMsg_presence", 1;
		}

	} elsif ($args->{switch} eq "0079" ||
		$args->{switch} eq "01DB" ||
		$args->{switch} eq "022B" ||
		$args->{switch} eq "02ED" ||
		$args->{switch} eq "01D9" ||
		$args->{switch} eq "07F8" ||
		$args->{switch} eq "0858") {
		# Actor Connected (new)

		if ($actor->isa('Actor::Player')) {
			my $domain = existsInList($config{friendlyAID}, unpack("V", $args->{ID})) ? 'parseMsg_presence' : 'parseMsg_presence/player';
			debug "Player Connected: ".$actor->name." ($actor->{binID}) Level $args->{lv} $sex_lut{$actor->{sex}} $jobs_lut{$actor->{jobID}} ($coordsTo{x}, $coordsTo{y})\n", $domain;

			Plugins::callHook('player', {player => $actor});  #backwards compatibailty

			Plugins::callHook('player_connected', {player => $actor});
		} else {
			debug "Unknown Connected: $args->{type} - ", "parseMsg";
		}

	} elsif ($args->{switch} eq "007B" ||
		$args->{switch} eq "0086" ||
		$args->{switch} eq "01DA" ||
		$args->{switch} eq "022C" ||
		$args->{switch} eq "02EC" ||
		$args->{switch} eq "07F7" ||
		$args->{switch} eq "0856") {
		# Actor Moved

		# Correct the direction in which they're looking
		my %vec;
		getVector(\%vec, \%coordsTo, \%coordsFrom);
		my $direction = int sprintf("%.0f", (360 - vectorToDegree(\%vec)) / 45);

		$actor->{look}{body} = $direction;
		$actor->{look}{head} = 0;

		if ($actor->isa('Actor::Player')) {
			debug "Player Moved: " . $actor->name . " ($actor->{binID}) Level $actor->{lv} $sex_lut{$actor->{sex}} $jobs_lut{$actor->{jobID}} - ($coordsFrom{x}, $coordsFrom{y}) -> ($coordsTo{x}, $coordsTo{y})\n", "parseMsg";
		} elsif ($actor->isa('Actor::Monster')) {
			debug "Monster Moved: " . $actor->nameIdx . " - ($coordsFrom{x}, $coordsFrom{y}) -> ($coordsTo{x}, $coordsTo{y})\n", "parseMsg";
		} elsif ($actor->isa('Actor::Pet')) {
			debug "Pet Moved: " . $actor->nameIdx . " - ($coordsFrom{x}, $coordsFrom{y}) -> ($coordsTo{x}, $coordsTo{y})\n", "parseMsg";
		} elsif ($actor->isa('Actor::Slave')) {
			debug "Slave Moved: " . $actor->nameIdx . " - ($coordsFrom{x}, $coordsFrom{y}) -> ($coordsTo{x}, $coordsTo{y})\n", "parseMsg";
		} elsif ($actor->isa('Actor::Portal')) {
			# This can never happen of course.
			debug "Portal Moved: " . $actor->nameIdx . " - ($coordsFrom{x}, $coordsFrom{y}) -> ($coordsTo{x}, $coordsTo{y})\n", "parseMsg";
		} elsif ($actor->isa('Actor::NPC')) {
			# Neither can this.
			debug "NPC Moved: " . $actor->nameIdx . " - ($coordsFrom{x}, $coordsFrom{y}) -> ($coordsTo{x}, $coordsTo{y})\n", "parseMsg";
		} else {
			debug "Unknown Actor Moved: " . $actor->nameIdx . " - ($coordsFrom{x}, $coordsFrom{y}) -> ($coordsTo{x}, $coordsTo{y})\n", "parseMsg";
		}

	} elsif ($args->{switch} eq "007C") {
		# Actor Spawned
		if ($actor->isa('Actor::Player')) {
			debug "Player Spawned: " . $actor->nameIdx . " $sex_lut{$actor->{sex}} $jobs_lut{$actor->{jobID}}\n", "parseMsg";
		} elsif ($actor->isa('Actor::Monster')) {
			debug "Monster Spawned: " . $actor->nameIdx . "\n", "parseMsg";
		} elsif ($actor->isa('Actor::Pet')) {
			debug "Pet Spawned: " . $actor->nameIdx . "\n", "parseMsg";
		} elsif ($actor->isa('Actor::Slave')) {
			debug "Slave Spawned: " . $actor->nameIdx . " $jobs_lut{$actor->{jobID}}\n", "parseMsg";
		} elsif ($actor->isa('Actor::Portal')) {
			# Can this happen?
			debug "Portal Spawned: " . $actor->nameIdx . "\n", "parseMsg";
		} elsif ($actor->isa('NPC')) {
			debug "NPC Spawned: " . $actor->nameIdx . "\n", "parseMsg";
		} else {
			debug "Unknown Spawned: " . $actor->nameIdx . "\n", "parseMsg";
		}
	}
}

sub actor_died_or_disappeared {
	my ($self,$args) = @_;
	return unless changeToInGameState();
	my $ID = $args->{ID};
	avoidList_ID($ID);

	if ($ID eq $accountID) {
		message T("You have died\n") if (!$char->{dead});
		Plugins::callHook('self_died');
		closeShop() unless !$shopstarted || $config{'dcOnDeath'} == -1 || $AI == AI::OFF;
		$char->{deathCount}++;
		$char->{dead} = 1;
		$char->{dead_time} = time;
		if ($char->{equipment}{arrow} && $char->{equipment}{arrow}{type} == 19) {
			delete $char->{equipment}{arrow};
		}

	} elsif (defined $monstersList->getByID($ID)) {
		my $monster = $monstersList->getByID($ID);
		if ($args->{type} == 0) {
			debug "Monster Disappeared: " . $monster->name . " ($monster->{binID})\n", "parseMsg_presence";
			$monster->{disappeared} = 1;

		} elsif ($args->{type} == 1) {
			debug "Monster Died: " . $monster->name . " ($monster->{binID})\n", "parseMsg_damage";
			$monster->{dead} = 1;

			if ((AI::action ne "attack" || AI::args(0)->{ID} eq $ID) &&
			    ($config{itemsTakeAuto_party} &&
			    ($monster->{dmgFromParty} > 0 ||
			     $monster->{dmgFromYou} > 0))) {
				AI::clear("items_take");
				ai_items_take($monster->{pos}{x}, $monster->{pos}{y},
					$monster->{pos_to}{x}, $monster->{pos_to}{y});
			}

		} elsif ($args->{type} == 2) { # What's this?
			debug "Monster Disappeared: " . $monster->name . " ($monster->{binID})\n", "parseMsg_presence";
			$monster->{disappeared} = 1;

		} elsif ($args->{type} == 3) {
			debug "Monster Teleported: " . $monster->name . " ($monster->{binID})\n", "parseMsg_presence";
			$monster->{teleported} = 1;
		}

		$monster->{gone_time} = time;
		$monsters_old{$ID} = $monster->deepCopy();
		Plugins::callHook('monster_disappeared', {monster => $monster});
		$monstersList->remove($monster);

	} elsif (defined $playersList->getByID($ID)) {
		my $player = $playersList->getByID($ID);
		if ($args->{type} == 1) {
			message TF("Player Died: %s (%d) %s %s\n", $player->name, $player->{binID}, $sex_lut{$player->{sex}}, $jobs_lut{$player->{jobID}});
			$player->{dead} = 1;
			$player->{dead_time} = time;
		} else {
			if ($args->{type} == 0) {
				debug "Player Disappeared: " . $player->name . " ($player->{binID}) $sex_lut{$player->{sex}} $jobs_lut{$player->{jobID}} ($player->{pos_to}{x}, $player->{pos_to}{y})\n", "parseMsg_presence";
				$player->{disappeared} = 1;
			} elsif ($args->{type} == 2) {
				debug "Player Disconnected: ".$player->name." ($player->{binID}) $sex_lut{$player->{sex}} $jobs_lut{$player->{jobID}} ($player->{pos_to}{x}, $player->{pos_to}{y})\n", "parseMsg_presence";
				$player->{disconnected} = 1;
			} elsif ($args->{type} == 3) {
				debug "Player Teleported: ".$player->name." ($player->{binID}) $sex_lut{$player->{sex}} $jobs_lut{$player->{jobID}} ($player->{pos_to}{x}, $player->{pos_to}{y})\n", "parseMsg_presence";
				$player->{teleported} = 1;
			} else {
				debug "Player Disappeared in an unknown way: ".$player->name." ($player->{binID}) $sex_lut{$player->{sex}} $jobs_lut{$player->{jobID}}\n", "parseMsg_presence";
				$player->{disappeared} = 1;
			}

			if ($ID ~~ @venderListsID) {
				binRemove(\@venderListsID, $ID);
				delete $venderLists{$ID};
			}

			$player->{gone_time} = time;
			$players_old{$ID} = $player->deepCopy();
			Plugins::callHook('player_disappeared', {player => $player});

			$playersList->remove($player);
		}

	} elsif ($players_old{$ID}) {
		if ($args->{type} == 2) {
			debug "Player Disconnected: " . $players_old{$ID}->name . "\n", "parseMsg_presence";
			$players_old{$ID}{disconnected} = 1;
		} elsif ($args->{type} == 3) {
			debug "Player Teleported: " . $players_old{$ID}->name . "\n", "parseMsg_presence";
			$players_old{$ID}{teleported} = 1;
		}

	} elsif (defined $portalsList->getByID($ID)) {
		my $portal = $portalsList->getByID($ID);
		debug "Portal Disappeared: " . $portal->name . " ($portal->{binID})\n", "parseMsg";
		$portal->{disappeared} = 1;
		$portal->{gone_time} = time;
		$portals_old{$ID} = $portal->deepCopy();
		$portalsList->remove($portal);

	} elsif (defined $npcsList->getByID($ID)) {
		my $npc = $npcsList->getByID($ID);
		debug "NPC Disappeared: " . $npc->name . " ($npc->{nameID})\n", "parseMsg";
		$npc->{disappeared} = 1;
		$npc->{gone_time} = time;
		$npcs_old{$ID} = $npc->deepCopy();
		$npcsList->remove($npc);

	} elsif (defined $petsList->getByID($ID)) {
		my $pet = $petsList->getByID($ID);
		debug "Pet Disappeared: " . $pet->name . " ($pet->{binID})\n", "parseMsg";
		$pet->{disappeared} = 1;
		$pet->{gone_time} = time;
		$petsList->remove($pet);

	} elsif (defined $slavesList->getByID($ID)) {
		my $slave = $slavesList->getByID($ID);
		if ($args->{type} == 1) {
			message TF("Slave Died: %s (%d) %s\n", $slave->name, $slave->{binID}, $slave->{actorType});
		} else {
			if ($args->{type} == 0) {
				debug "Slave Disappeared: " . $slave->name . " ($slave->{binID}) $slave->{actorType} ($slave->{pos_to}{x}, $slave->{pos_to}{y})\n", "parseMsg_presence";
				$slave->{disappeared} = 1;
			} elsif ($args->{type} == 2) {
				debug "Slave Disconnected: ".$slave->name." ($slave->{binID}) $slave->{actorType} ($slave->{pos_to}{x}, $slave->{pos_to}{y})\n", "parseMsg_presence";
				$slave->{disconnected} = 1;
			} elsif ($args->{type} == 3) {
				debug "Slave Teleported: ".$slave->name." ($slave->{binID}) $slave->{actorType} ($slave->{pos_to}{x}, $slave->{pos_to}{y})\n", "parseMsg_presence";
				$slave->{teleported} = 1;
			} else {
				debug "Slave Disappeared in an unknown way: ".$slave->name." ($slave->{binID}) $slave->{actorType}\n", "parseMsg_presence";
				$slave->{disappeared} = 1;
			}

			$slave->{gone_time} = time;
			Plugins::callHook('slave_disappeared', {slave => $slave});
		}

		$slavesList->remove($slave);

	} else {
		debug "Unknown Disappeared: ".getHex($ID)."\n", "parseMsg";
	}
}

sub actor_action {
	my ($self,$args) = @_;
	return unless changeToInGameState();

	$args->{damage} = intToSignedShort($args->{damage});
	if ($args->{type} == ACTION_ITEMPICKUP) {
		# Take item
		my $source = Actor::get($args->{sourceID});
		my $verb = $source->verb('pick up', 'picks up');
		my $target = getActorName($args->{targetID});
		debug "$source $verb $target\n", 'parseMsg_presence';

		my $item = $itemsList->getByID($args->{targetID});
		$item->{takenBy} = $args->{sourceID} if ($item);

	} elsif ($args->{type} == ACTION_SIT) {
		# Sit
		my ($source, $verb) = getActorNames($args->{sourceID}, 0, 'are', 'is');
		if ($args->{sourceID} eq $accountID) {
			message T("You are sitting.\n") if (!$char->{sitting});
			$char->{sitting} = 1;
			AI::queue("sitAuto") unless (AI::inQueue("sitAuto")) || $ai_v{sitAuto_forcedBySitCommand};
		} else {
			message TF("%s is sitting.\n", getActorName($args->{sourceID})), 'parseMsg_statuslook', 2;
			my $player = $playersList->getByID($args->{sourceID});
			$player->{sitting} = 1 if ($player);
		}
		Misc::checkValidity("actor_action (take item)");

	} elsif ($args->{type} == ACTION_STAND) {
		# Stand
		my ($source, $verb) = getActorNames($args->{sourceID}, 0, 'are', 'is');
		if ($args->{sourceID} eq $accountID) {
			message T("You are standing.\n") if ($char->{sitting});
			if ($config{sitAuto_idle}) {
				$timeout{ai_sit_idle}{time} = time;
			}
			$char->{sitting} = 0;
		} else {
			message TF("%s is standing.\n", getActorName($args->{sourceID})), 'parseMsg_statuslook', 2;
			my $player = $playersList->getByID($args->{sourceID});
			$player->{sitting} = 0 if ($player);
		}
		Misc::checkValidity("actor_action (stand)");

	} else {
		# Attack
		my $dmgdisplay;
		my $totalDamage = $args->{damage} + $args->{dual_wield_damage};
		if ($totalDamage == 0) {
			$dmgdisplay = T("Miss!");
			$dmgdisplay .= "!" if ($args->{type} == ACTION_ATTACK_LUCKY); # lucky dodge
		} else {
			$dmgdisplay = $args->{div} > 1
				? sprintf '%d*%d', $args->{damage} / $args->{div}, $args->{div}
				: $args->{damage}
			;
			$dmgdisplay .= "!" if ($args->{type} == ACTION_ATTACK_CRITICAL); # critical hit
			$dmgdisplay .= " + $args->{dual_wield_damage}" if $args->{dual_wield_damage};
		}

		Misc::checkValidity("actor_action (attack 1)");

		updateDamageTables($args->{sourceID}, $args->{targetID}, $totalDamage);

		Misc::checkValidity("actor_action (attack 2)");

		my $source = Actor::get($args->{sourceID});
		my $target = Actor::get($args->{targetID});
		my $verb = $source->verb('attack', 'attacks');

		$target->{sitting} = 0 unless $args->{type} == ACTION_ATTACK_NOMOTION || $args->{type} == ACTION_ATTACK_MULTIPLE_NOMOTION || $totalDamage == 0;

		my $msg = attack_string($source, $target, $dmgdisplay, ($args->{src_speed}));
		Plugins::callHook('packet_attack', {sourceID => $args->{sourceID}, targetID => $args->{targetID}, msg => \$msg, dmg => $totalDamage, type => $args->{type}});

		my $status = sprintf("[%3d/%3d]", percent_hp($char), percent_sp($char));

		Misc::checkValidity("actor_action (attack 3)");

		if ($args->{sourceID} eq $accountID) {
			message("$status $msg", $totalDamage > 0 ? "attackMon" : "attackMonMiss");
			if ($startedattack) {
				$monstarttime = time();
				$monkilltime = time();
				$startedattack = 0;
			}
			Misc::checkValidity("actor_action (attack 4)");
			calcStat($args->{damage});
			Misc::checkValidity("actor_action (attack 5)");

		} elsif ($args->{targetID} eq $accountID) {
			message("$status $msg", $args->{damage} > 0 ? "attacked" : "attackedMiss");
			if ($args->{damage} > 0) {
				$damageTaken{$source->{name}}{attack} += $args->{damage};
			}

		} elsif ($char->{slaves} && $char->{slaves}{$args->{sourceID}}) {
			message(sprintf("[%3d/%3d]", $char->{slaves}{$args->{sourceID}}{hpPercent}, $char->{slaves}{$args->{sourceID}}{spPercent}) . " $msg", $totalDamage > 0 ? "attackMon" : "attackMonMiss");

		} elsif ($char->{slaves} && $char->{slaves}{$args->{targetID}}) {
			message(sprintf("[%3d/%3d]", $char->{slaves}{$args->{targetID}}{hpPercent}, $char->{slaves}{$args->{targetID}}{spPercent}) . " $msg", $args->{damage} > 0 ? "attacked" : "attackedMiss");

		} else {
			debug("$msg", 'parseMsg_damage');
		}

		Misc::checkValidity("actor_action (attack 6)");
	}
}

sub actor_info {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	debug "Received object info: $args->{name}\n", "parseMsg_presence/name", 2;

	my $player = $playersList->getByID($args->{ID});
	if ($player) {
		# 0095: This packet tells us the names of players who aren't in a guild.
		# 0195: Receive names of players who are in a guild.
		# FIXME: There is more to this packet than just party name and guild name.
		# This packet is received when you leave a guild
		# (with cryptic party and guild name fields, at least for now)
		$player->setName(bytesToString($args->{name}));
		$player->{info} = 1;

		$player->{party}{name} = bytesToString($args->{partyName}) if defined $args->{partyName};
		$player->{guild}{name} = bytesToString($args->{guildName}) if defined $args->{guildName};
		$player->{guild}{title} = bytesToString($args->{guildTitle}) if defined $args->{guildTitle};

		message "Player Info: " . $player->nameIdx . "\n", "parseMsg_presence", 2;
		updatePlayerNameCache($player);
		Plugins::callHook('charNameUpdate', {player => $player});
	}

	my $monster = $monstersList->getByID($args->{ID});
	if ($monster) {
		my $name = bytesToString($args->{name});
		$name =~ s/^\s+|\s+$//g;
		debug "Monster Info: $name ($monster->{binID})\n", "parseMsg", 2;
		$monster->{name_given} = $name;
		$monster->{info} = 1;
		if ($monsters_lut{$monster->{nameID}} eq "") {
			$monster->setName($name);
			$monsters_lut{$monster->{nameID}} = $name;
			updateMonsterLUT(Settings::getTableFilename("monsters.txt"), $monster->{nameID}, $name);
		}
	}

	my $npc = $npcs{$args->{ID}};
	if ($npc) {
		$npc->setName(bytesToString($args->{name}));
		$npc->{info} = 1;
		if ($config{debug} >= 2) {
			my $binID = binFind(\@npcsID, $args->{ID});
			debug "NPC Info: $npc->{name} ($binID)\n", "parseMsg", 2;
		}

		my $location = $field->baseName . " $npc->{pos}{x} $npc->{pos}{y}";
		if (!$npcs_lut{$location}) {
			$npcs_lut{$location} = $npc->{name};
			updateNPCLUT(Settings::getTableFilename("npcs.txt"), $location, $npc->{name});
		}
	}

	my $pet = $pets{$args->{ID}};
	if ($pet) {
		my $name = bytesToString($args->{name});
		$pet->{name_given} = $name;
		$pet->setName($name);
		$pet->{info} = 1;
		if ($config{debug} >= 2) {
			my $binID = binFind(\@petsID, $args->{ID});
			debug "Pet Info: $pet->{name_given} ($binID)\n", "parseMsg", 2;
		}
	}

	my $slave = $slavesList->getByID($args->{ID});
	if ($slave) {
		my $name = bytesToString($args->{name});
		$slave->{name_given} = $name;
		$slave->setName($name);
		$slave->{info} = 1;
		my $binID = binFind(\@slavesID, $args->{ID});
		debug "Slave Info: $name ($binID)\n", "parseMsg_presence", 2;
		updatePlayerNameCache($slave);
	}

	# TODO: $args->{ID} eq $accountID
}

sub actor_look_at {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	my $actor = Actor::get($args->{ID});
	$actor->{look}{head} = $args->{head};
	$actor->{look}{body} = $args->{body};
	debug $actor->nameString . " looks at $args->{body}, $args->{head}\n", "parseMsg";
}

sub actor_movement_interrupted {
	my ($self, $args) = @_;
	return unless changeToInGameState();
	my %coords;
	$coords{x} = $args->{x};
	$coords{y} = $args->{y};

	my $actor = Actor::get($args->{ID});
	$actor->{pos} = {%coords};
	$actor->{pos_to} = {%coords};
	if ($actor->isa('Actor::You') || $actor->isa('Actor::Player')) {
		$actor->{sitting} = 0;
	}
	if ($actor->isa('Actor::You')) {
		debug "Movement interrupted, your coordinates: $coords{x}, $coords{y}\n", "parseMsg_move";
		AI::clear("move");
	}
	if ($char->{homunculus} && $char->{homunculus}{ID} eq $actor->{ID}) {
		AI::clear("move");
	}
}

sub actor_trapped {
	my ($self, $args) = @_;
	# original comment was that ID is not a valid ID
	# but it seems to be, at least on eAthena/Freya
	my $actor = Actor::get($args->{ID});
	debug "$actor->nameString() is trapped.\n";
}

sub area_spell_disappears {
	my ($self, $args) = @_;

	# The area effect spell with ID dissappears
	my $ID = $args->{ID};
	my $spell = $spells{$ID};
	debug "Area effect ".getSpellName($spell->{type})." ($spell->{binID}) from ".getActorName($spell->{sourceID})." disappeared from ($spell->{pos}{x}, $spell->{pos}{y})\n", "skill", 2;
	delete $spells{$ID};
	binRemove(\@spellsID, $ID);
}

sub arrow_none {
	my ($self, $args) = @_;

	my $type = $args->{type};
	if ($type == 0) {
		delete $char->{'arrow'};
		if ($config{'dcOnEmptyArrow'}) {
			$interface->errorDialog(T("Please equip arrow first."));
			quit();
		} else {
			error T("Please equip arrow first.\n");
		}
	} elsif ($type == 1) {
		debug "You can't Attack or use Skills because your Weight Limit has been exceeded.\n";
	} elsif ($type == 2) {
		debug "You can't use Skills because Weight Limit has been exceeded.\n";
	} elsif ($type == 3) {
		debug "Arrow equipped\n";
	}
}

sub arrowcraft_list {
	my ($self, $args) = @_;

	my $newmsg;
	my $msg = $args->{RAW_MSG};
	my $msg_size = $args->{RAW_MSG_SIZE};
	$self->decrypt(\$newmsg, substr($msg, 4));
	$msg = substr($msg, 0, 4).$newmsg;

	undef @arrowCraftID;
	for (my $i = 4; $i < $msg_size; $i += 2) {
		my $ID = unpack("v1", substr($msg, $i, 2));
		my $item = $char->inventory->getByNameID($ID);
		binAdd(\@arrowCraftID, $item->{invIndex});
	}

	message T("Received Possible Arrow Craft List - type 'arrowcraft'\n");
}

sub attack_range {
	my ($self, $args) = @_;

	my $type = $args->{type};
	debug "Your attack range is: $type\n";
	return unless changeToInGameState();

	$char->{attack_range} = $type;
	if ($config{attackDistanceAuto} && $config{attackDistance} != $type) {
		message TF("Autodetected attackDistance = %s\n", $type), "success";
		configModify('attackDistance', $type, 1);
		configModify('attackMaxDistance', $type, 1);
	}
}


# 0x803
sub booking_register_request {
	my ($self, $args) = @_;
	my $result = $args->{result};

	if ($result == 0) {
	message T("Booking successfully created!\n"), "booking";
	} elsif ($result == 2) {
	error T("You already got a reservation group active!\n"), "booking";
	} else {
	error TF("Unknown error in creating the group booking (Error %s)\n", $result), "booking";
	}
}

# 0x805
sub booking_search_request {
	my ($self, $args) = @_;

	if (length($args->{innerData}) == 0) {
		error T("Without results!\n"), "booking";
		return;
	}

	message T("-------------- Booking Search ---------------\n");
	for (my $offset = 0; $offset < length($args->{innerData}); $offset += 48) {
		my ($index, $charName, $expireTime, $level, $mapID, @job) = unpack("V Z24 V s8", substr($args->{innerData}, $offset, 48));
		message swrite(
			T("Name: \@<<<<<<<<<<<<<<<<<<<<<<<<	Index: \@>>>>\n" .
			"Created: \@<<<<<<<<<<<<<<<<<<<<<	Level: \@>>>\n" .
			"MapID: \@<<<<<\n".
			"Job: \@<<<< \@<<<< \@<<<< \@<<<< \@<<<<\n" .
			"---------------------------------------------"),
			[bytesToString($charName), $index, getFormattedDate($expireTime), $level, $mapID, @job]), "booking";
	}
}

# 0x807
sub booking_delete_request {
	my ($self, $args) = @_;
	my $result = $args->{result};

	if ($result == 0) {
	message T("Reserve deleted successfully!\n"), "booking";
	} elsif ($result == 3) {
	error T("You're not with a group booking active!\n"), "booking";
	} else {
	error TF("Unknown error in deletion of group booking (Error %s)\n", $result), "booking";
	}
}

# 0x809
sub booking_insert {
	my ($self, $args) = @_;

	message TF("%s has created a new group booking (index: %s)\n", bytesToString($args->{name}), $args->{index});
}

# 0x80A
sub booking_update {
	my ($self, $args) = @_;

	message TF("Reserve index of %s has changed its settings\n", $args->{index});
}

# 0x80B
sub booking_delete {
	my ($self, $args) = @_;

	message TF("Deleted reserve group index %s\n", $args->{index});
}

sub buy_result {
	my ($self, $args) = @_;
	if ($args->{fail} == 0) {
		message T("Buy completed.\n"), "success";
	} elsif ($args->{fail} == 1) {
		error T("Buy failed (insufficient zeny).\n");
	} elsif ($args->{fail} == 2) {
		error T("Buy failed (insufficient weight capacity).\n");
	} elsif ($args->{fail} == 3) {
		error T("Buy failed (too many different inventory items).\n");
	} elsif ($args->{fail} == 4) {
		error T("Buy failed (item does not exist in store).\n");
	} elsif ($args->{fail} == 5) {
		error T("Buy failed (item cannot be exchanged).\n");
	} elsif ($args->{fail} == 6) {
		error T("Buy failed (invalid store).\n");
	} else {
		error TF("Buy failed (failure code %s).\n", $args->{fail});
	}
}

sub card_merge_list {
	my ($self, $args) = @_;

	# You just requested a list of possible items to merge a card into
	# The RO client does this when you double click a card
	my $newmsg;
	my $msg = $args->{RAW_MSG};
	$self->decrypt(\$newmsg, substr($msg, 4));
	$msg = substr($msg, 0, 4).$newmsg;
	my ($len) = unpack("x2 v", $msg); # TODO: remove this decrypt cruft

	my $display;
	$display .= T("-----Card Merge Candidates-----\n");

	my $index;
	for (my $i = 4; $i < $len; $i += 2) {
		$index = unpack('v', substr($msg, $i, 2));
		my $item = $char->inventory->getByServerIndex($index);
		binAdd(\@cardMergeItemsID, $item->{invIndex});
		$display .= "$item->{invIndex} $item->{name}\n";
	}

	$display .= "-------------------------------\n";
	message $display, "list";
}


sub card_merge_status {
	my ($self, $args) = @_;

	# something about successful compound?
	my $item_index = $args->{item_index};
	my $card_index = $args->{card_index};
	my $fail = $args->{fail};

	if ($fail) {
		message T("Card merging failed\n");
	} else {
		my $item = $char->inventory->getByServerIndex($item_index);
		my $card = $char->inventory->getByServerIndex($card_index);
		message TF("%s has been successfully merged into %s\n",
			$card->{name}, $item->{name}), "success";

		# Remove one of the card
		$card->{amount} -= 1;
		if ($card->{amount} <= 0) {
			$char->inventory->remove($card);
		}

		# Rename the slotted item now
		# FIXME: this is unoptimized
		use bytes;
		no encoding 'utf8';
		my $newcards = '';
		my $addedcard;
		for (my $i = 0; $i < 4; $i++) {
			my $cardData = substr($item->{cards}, $i * 2, 2);
			if (unpack("v", $cardData)) {
				$newcards .= $cardData;
			} elsif (!$addedcard) {
				$newcards .= pack('v', $card->{nameID});
				$addedcard = 1;
			} else {
				$newcards .= pack("v", 0);
			}
		}
		$item->{cards} = $newcards;
		$item->setName(itemName($item));
	}

	undef @cardMergeItemsID;
	undef $cardMergeIndex;
}

sub cart_info {
	my ($self, $args) = @_;

	$cart{items} = $args->{items};
	$cart{items_max} = $args->{items_max};
	$cart{weight} = int($args->{weight} / 10);
	$cart{weight_max} = int($args->{weight_max} / 10);
	$cart{exists} = 1;
	debug "[cart_info] received.\n", "parseMsg";
}

sub cart_add_failed {
	my ($self, $args) = @_;

	my $reason;
	if ($args->{fail} == 0) {
		$reason = T('overweight');
	} elsif ($args->{fail} == 1) {
		$reason = T('too many items');
	} else {
		$reason = TF("Unknown code %s",$args->{fail});
	}
	error TF("Can't Add Cart Item (%s)\n", $reason);
}

sub cart_items_nonstackable {
	my ($self, $args) = @_;

	$self->_items_list({
		# TODO: different classes for inventory/cart/storage items
		class => 'Actor::Item',
		hook => 'packet_cart',
		debug_str => 'Non-Stackable Cart Item',
		items => [$self->parse_items_nonstackable($args)],
		getter => sub { $cart{inventory}[$_[0]{index}] },
		adder => sub { $cart{inventory}[$_[0]{index}] = $_[0] },
	});

	$ai_v{'inventory_time'} = time + 1;
	$ai_v{'cart_time'} = time + 1;
}

sub cart_items_stackable {
	my ($self, $args) = @_;

	$self->_items_list({
		class => 'Actor::Item',
		hook => 'packet_cart',
		debug_str => 'Stackable Cart Item',
		items => [$self->parse_items_stackable($args)],
		getter => sub { $cart{inventory}[$_[0]{index}] },
		adder => sub { $cart{inventory}[$_[0]{index}] = $_[0] },
	});

	$ai_v{'inventory_time'} = time + 1;
	$ai_v{'cart_time'} = time + 1;
}

sub cart_item_added {
	my ($self, $args) = @_;

	my $item = $cart{inventory}[$args->{index}] ||= Actor::Item->new;
	if ($item->{amount}) {
		$item->{amount} += $args->{amount};
	} else {
		$item->{index} = $args->{index};
		$item->{nameID} = $args->{nameID};
		$item->{amount} = $args->{amount};
		$item->{identified} = $args->{identified};
		$item->{broken} = $args->{broken};
		$item->{upgrade} = $args->{upgrade};
		$item->{cards} = $args->{cards};
		$item->{type} = $args->{type} if (exists $args->{type});
		$item->{name} = itemName($item);
	}
	message TF("Cart Item Added: %s (%d) x %s\n", $item->{name}, $args->{index}, $args->{amount});
	$itemChange{$item->{name}} += $args->{amount};
	$args->{item} = $item;
}

sub cash_dealer {
	my ($self, $args) = @_;

	undef @cashList;
	my $cashList = 0;
	$char->{cashpoint} = unpack("x4 V", $args->{RAW_MSG});

	for (my $i = 8; $i < $args->{RAW_MSG_SIZE}; $i += 11) {
		my ($price, $dcprice, $type, $ID) = unpack("V2 C v", substr($args->{RAW_MSG}, $i, 11));
		my $store = $cashList[$cashList] = {};
		# TODO: use itemName() or itemNameSimple()?
		my $display = ($items_lut{$ID} ne "") ? $items_lut{$ID} : "Unknown $ID";
		$store->{name} = $display;
		$store->{nameID} = $ID;
		$store->{type} = $type;
		$store->{price} = $dcprice;
		$cashList++;
	}

	$ai_v{npc_talk}{talk} = 'cash';
	# continue talk sequence now
	$ai_v{npc_talk}{time} = Time::HiRes::time;

	message TF("------------CashList (Cash Point: %-5d)-------------\n" .
		"#    Name                    Type               Price\n", $char->{cashpoint}), "list";
	my $display;
	for (my $i = 0; $i < @cashList; $i++) {
		$display = $cashList[$i]{name};
		message(swrite(
			"@<<< @<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<< @>>>>>>>p",
			[$i, $display, $itemTypes_lut{$cashList[$i]{type}}, $cashList[$i]{price}]),
			"list");
	}
	message("-----------------------------------------------------\n", "list");
}

sub combo_delay {
	my ($self, $args) = @_;

	$char->{combo_packet} = ($args->{delay}); #* 15) / 100000;
	# How was the above formula derived? I think it's better that the manipulation be
	# done in functions.pl (or whatever sub that handles this) instead of here.

	$args->{actor} = Actor::get($args->{ID});
	my $verb = $args->{actor}->verb('have', 'has');
	debug "$args->{actor} $verb combo delay $args->{delay}\n", "parseMsg_comboDelay";
}

sub cart_item_removed {
	my ($self, $args) = @_;

	my ($index, $amount) = @{$args}{qw(index amount)};

	my $item = $cart{inventory}[$index];
	$item->{amount} -= $amount;
	message TF("Cart Item Removed: %s (%d) x %s\n", $item->{name}, $index, $amount);
	$itemChange{$item->{name}} -= $amount;
	if ($item->{amount} <= 0) {
		$cart{'inventory'}[$index] = undef;
	}
	$args->{item} = $item;
}

sub change_to_constate25 {
	$net->setState(2.5);
	undef $accountID;
}

sub character_creation_failed {
	my ($self, $args) = @_;
	if ($args->{flag} == 0x0) {
		message T("Charname already exists.\n"), "info";
	} elsif ($args->{flag} == 0xFF) {
		message T("Char creation denied.\n"), "info";
	} elsif ($args->{flag} == 0x01) {
		message T("You are underaged.\n"), "info";
	} else {
		message T("Character creation failed. " .
			"If you didn't make any mistake, then the name you chose already exists.\n"), "info";
	}
	if (charSelectScreen() == 1) {
		$net->setState(3);
		$firstLoginMap = 1;
		$startingzeny = $chars[$config{'char'}]{'zeny'} unless defined $startingzeny;
		$sentWelcomeMessage = 1;
	}
}

sub character_deletion_successful {
	if (defined $AI::temp::delIndex) {
		message TF("Character %s (%d) deleted.\n", $chars[$AI::temp::delIndex]{name}, $AI::temp::delIndex), "info";
		delete $chars[$AI::temp::delIndex];
		undef $AI::temp::delIndex;
		for (my $i = 0; $i < @chars; $i++) {
			delete $chars[$i] if ($chars[$i] && !scalar(keys %{$chars[$i]}))
		}
	} else {
		message T("Character deleted.\n"), "info";
	}

	if (charSelectScreen() == 1) {
		$net->setState(3);
		$firstLoginMap = 1;
		$startingzeny = $chars[$config{'char'}]{'zeny'} unless defined $startingzeny;
		$sentWelcomeMessage = 1;
	}
}

sub character_deletion_failed {
	error T("Character cannot be deleted. Your e-mail address was probably wrong.\n");
	undef $AI::temp::delIndex;
	if (charSelectScreen() == 1) {
		$net->setState(3);
		$firstLoginMap = 1;
		$startingzeny = $chars[$config{'char'}]{'zeny'} unless defined $startingzeny;
		$sentWelcomeMessage = 1;
	}
}

sub character_moves {
	my ($self, $args) = @_;

	return unless changeToInGameState();
	makeCoordsFromTo($char->{pos}, $char->{pos_to}, $args->{coords});
	my $dist = sprintf("%.1f", distance($char->{pos}, $char->{pos_to}));
	debug "You're moving from ($char->{pos}{x}, $char->{pos}{y}) to ($char->{pos_to}{x}, $char->{pos_to}{y}) - distance $dist\n", "parseMsg_move";
	$char->{time_move} = time;
	$char->{time_move_calc} = distance($char->{pos}, $char->{pos_to}) * ($char->{walk_speed} || 0.12);

	# Correct the direction in which we're looking
	my (%vec, $degree);
	getVector(\%vec, $char->{pos_to}, $char->{pos});
	$degree = vectorToDegree(\%vec);
	if (defined $degree) {
		my $direction = int sprintf("%.0f", (360 - $degree) / 45);
		$char->{look}{body} = $direction & 0x07;
		$char->{look}{head} = 0;
	}

	# Ugly; AI code in network subsystem! This must be fixed.
	if (AI::action eq "mapRoute" && $config{route_escape_reachedNoPortal} && $dist eq "0.0"){
	   if (!$portalsID[0]) {
		if ($config{route_escape_shout} ne "" && !defined($timeout{ai_route_escape}{time})){
			sendMessage("c", $config{route_escape_shout});
		}
 	   	 $timeout{ai_route_escape}{time} = time;
	   	 AI::queue("escape");
	   }
	}
}

sub character_name {
	my ($self, $args) = @_;
	my $name; # Type: String

	$name = bytesToString($args->{name});
	debug "Character name received: $name\n";
}


sub character_status {
	my ($self, $args) = @_;

	my $actor = Actor::get($args->{ID});

	if ($args->{switch} eq '028A') {
		$actor->{lv} = $args->{lv}; # TODO: test if it is ok to use this piece of information
		$actor->{opt3} = $args->{opt3};
	} elsif ($args->{switch} eq '0229' || $args->{switch} eq '0119') {
		$actor->{opt1} = $args->{opt1};
		$actor->{opt2} = $args->{opt2};
	}

	$actor->{option} = $args->{option};

	setStatus($actor, $args->{opt1}, $args->{opt2}, $args->{option});
}

sub chat_created {
	my ($self, $args) = @_;

	$currentChatRoom = $accountID;
	$chatRooms{$accountID} = {%createdChatRoom};
	binAdd(\@chatRoomsID, $accountID);
	binAdd(\@currentChatRoomUsers, $char->{name});
	message T("Chat Room Created\n");
}

sub chat_info {
	my ($self, $args) = @_;

	my $title;
	$self->decrypt(\$title, $args->{title});
	$title = bytesToString($title);

	my $chat = $chatRooms{$args->{ID}};
	if (!$chat || !%{$chat}) {
		$chat = $chatRooms{$args->{ID}} = {};
		binAdd(\@chatRoomsID, $args->{ID});
	}
	$chat->{title} = $title;
	$chat->{ownerID} = $args->{ownerID};
	$chat->{limit} = $args->{limit};
	$chat->{public} = $args->{public};
	$chat->{num_users} = $args->{num_users};

	Plugins::callHook('packet_chatinfo', {
	  chatID => $args->{ID},
	  ownerID => $args->{ownerID},
	  title => $title,
	  limit => $args->{limit},
	  public => $args->{public},
	  num_users => $args->{num_users}
	});
}

sub chat_join_result {
	my ($self, $args) = @_;

	if ($args->{type} == 1) {
		message T("Can't join Chat Room - Incorrect Password\n");
	} elsif ($args->{type} == 2) {
		message T("Can't join Chat Room - You're banned\n");
	}
}

sub chat_modified {
	my ($self, $args) = @_;

	my $title;
	$self->decrypt(\$title, $args->{title});
	$title = bytesToString($title);

	my ($ownerID, $ID, $limit, $public, $num_users) = @{$args}{qw(ownerID ID limit public num_users)};

	if ($ownerID eq $accountID) {
		$chatRooms{new}{title} = $title;
		$chatRooms{new}{ownerID} = $ownerID;
		$chatRooms{new}{limit} = $limit;
		$chatRooms{new}{public} = $public;
		$chatRooms{new}{num_users} = $num_users;
	} else {
		$chatRooms{$ID}{title} = $title;
		$chatRooms{$ID}{ownerID} = $ownerID;
		$chatRooms{$ID}{limit} = $limit;
		$chatRooms{$ID}{public} = $public;
		$chatRooms{$ID}{num_users} = $num_users;
	}
	message T("Chat Room Properties Modified\n");
}

sub chat_newowner {
	my ($self, $args) = @_;

	my $user = bytesToString($args->{user});
	if ($args->{type} == 0) {
		if ($user eq $char->{name}) {
			$chatRooms{$currentChatRoom}{ownerID} = $accountID;
		} else {
			my $players = $playersList->getItems();
			my $player;
			foreach my $p (@{$players}) {
				if ($p->{name} eq $user) {
					$player = $p;
					last;
				}
			}

			if ($player) {
				my $key = $player->{ID};
				$chatRooms{$currentChatRoom}{ownerID} = $key;
			}
		}
		$chatRooms{$currentChatRoom}{users}{$user} = 2;
	} else {
		$chatRooms{$currentChatRoom}{users}{$user} = 1;
	}
}

sub chat_user_join {
	my ($self, $args) = @_;

	my $user = bytesToString($args->{user});
	if ($currentChatRoom ne "") {
		binAdd(\@currentChatRoomUsers, $user);
		$chatRooms{$currentChatRoom}{users}{$user} = 1;
		$chatRooms{$currentChatRoom}{num_users} = $args->{num_users};
		message TF("%s has joined the Chat Room\n", $user);
	}
}

sub chat_user_leave {
	my ($self, $args) = @_;

	my $user = bytesToString($args->{user});
	delete $chatRooms{$currentChatRoom}{users}{$user};
	binRemove(\@currentChatRoomUsers, $user);
	$chatRooms{$currentChatRoom}{num_users} = $args->{num_users};
	if ($user eq $char->{name}) {
		binRemove(\@chatRoomsID, $currentChatRoom);
		delete $chatRooms{$currentChatRoom};
		undef @currentChatRoomUsers;
		$currentChatRoom = "";
		message T("You left the Chat Room\n");
	} else {
		message TF("%s has left the Chat Room\n", $user);
	}
}


sub cast_cancelled {
	my ($self, $args) = @_;

	# Cast is cancelled
	my $ID = $args->{ID};

	my $source = Actor::get($ID);
	$source->{cast_cancelled} = time;
	my $skill = $source->{casting}->{skill};
	my $skillName = $skill ? $skill->getName() : T('Unknown');
	my $domain = ($ID eq $accountID) ? "selfSkill" : "skill";
	message sprintf($source->verb(T("%s failed to cast %s\n"), T("%s failed to cast %s\n")), $source, $skillName), $domain;
	Plugins::callHook('packet_castCancelled', {
		sourceID => $ID
	});
	delete $source->{casting};
}

sub chat_removed {
	my ($self, $args) = @_;

	binRemove(\@chatRoomsID, $args->{ID});
	delete $chatRooms{ $args->{ID} };
}

sub deal_add_other {
	my ($self, $args) = @_;

	if ($args->{nameID} > 0) {
		my $item = $currentDeal{other}{ $args->{nameID} } ||= {};
		$item->{amount} += $args->{amount};
		$item->{nameID} = $args->{nameID};
		$item->{identified} = $args->{identified};
		$item->{broken} = $args->{broken};
		$item->{upgrade} = $args->{upgrade};
		$item->{cards} = $args->{cards};
		$item->{name} = itemName($item);
		message TF("%s added Item to Deal: %s x %s\n", $currentDeal{name}, $item->{name}, $args->{amount}), "deal";
	} elsif ($args->{amount} > 0) {
		$currentDeal{other_zeny} += $args->{amount};
		my $amount = formatNumber($args->{amount});
		message TF("%s added %s z to Deal\n", $currentDeal{name}, $amount), "deal";
	}
}

sub deal_add_you {
	my ($self, $args) = @_;

	if ($args->{fail} == 1) {
		error T("That person is overweight; you cannot trade.\n"), "deal";
		return;
	} elsif ($args->{fail} == 2) {
		error T("This item cannot be traded.\n"), "deal";
		return;
	} elsif ($args->{fail}) {
		error TF("You cannot trade (fail code %s).\n", $args->{fail}), "deal";
		return;
	}

	return unless $args->{index} > 0;

	my $item = $char->inventory->getByServerIndex($args->{index});
	# FIXME: quickly add two items => lastItemAmount is lost => inventory corruption; see also Misc::dealAddItem
	# FIXME: what will be in case of two items with the same nameID?
	# TODO: no info about items is stored
	$currentDeal{you}{$item->{nameID}}{amount} += $currentDeal{lastItemAmount};
	$currentDeal{you}{$item->{nameID}}{nameID} = $item->{nameID};
	$item->{amount} -= $currentDeal{lastItemAmount};
	message TF("You added Item to Deal: %s x %s\n", $item->{name}, $currentDeal{lastItemAmount}), "deal";
	$itemChange{$item->{name}} -= $currentDeal{lastItemAmount};
	$currentDeal{you_items}++;
	$args->{item} = $item;
	$char->inventory->remove($item) if ($item->{amount} <= 0);
}

sub deal_begin {
	my ($self, $args) = @_;

	if ($args->{type} == 0) {
		error T("That person is too far from you to trade.\n"), "deal";
	} elsif ($args->{type} == 2) {
		error T("That person is in another deal.\n"), "deal";
	} elsif ($args->{type} == 3) {
		if (%incomingDeal) {
			$currentDeal{name} = $incomingDeal{name};
			undef %incomingDeal;
		} else {
			my $ID = $outgoingDeal{ID};
			my $player;
			$player = $playersList->getByID($ID) if (defined $ID);
			$currentDeal{ID} = $ID;
			if ($player) {
				$currentDeal{name} = $player->{name};
			} else {
				$currentDeal{name} = T('Unknown #') . unpack("V", $ID);
			}
			undef %outgoingDeal;
		}
		message TF("Engaged Deal with %s\n", $currentDeal{name}), "deal";
	} elsif ($args->{type} == 5) {
		error T("That person is opening storage.\n"), "deal";
	} else {
		error TF("Deal request failed (unknown error %s).\n", $args->{type}), "deal";
	}
}

sub deal_cancelled {
	undef %incomingDeal;
	undef %outgoingDeal;
	undef %currentDeal;
	message T("Deal Cancelled\n"), "deal";
}

sub deal_complete {
	undef %outgoingDeal;
	undef %incomingDeal;
	undef %currentDeal;
	message T("Deal Complete\n"), "deal";
}

sub deal_finalize {
	my ($self, $args) = @_;
	if ($args->{type} == 1) {
		$currentDeal{other_finalize} = 1;
		message TF("%s finalized the Deal\n", $currentDeal{name}), "deal";

	} else {
		$currentDeal{you_finalize} = 1;
		# FIXME: shouldn't we do this when we actually complete the deal?
		$char->{zeny} -= $currentDeal{you_zeny};
		message T("You finalized the Deal\n"), "deal";
	}
}

sub deal_request {
	my ($self, $args) = @_;
	my $level = $args->{level} || 'Unknown'; # TODO: store this info
	my $user = bytesToString($args->{user});

	$incomingDeal{name} = $user;
	$timeout{ai_dealAutoCancel}{time} = time;
	message TF("%s (level %s) Requests a Deal\n", $user, $level), "deal";
	message T("Type 'deal' to start dealing, or 'deal no' to deny the deal.\n"), "deal";
}

sub devotion {
	my ($self, $args) = @_;
	my $msg = '';
	my $source = Actor::get($args->{sourceID});

	undef $devotionList->{$args->{sourceID}};
	for (my $i = 0; $i < 5; $i++) {
		my $ID = substr($args->{targetIDs}, $i*4, 4);
		last if unpack("V", $ID) == 0;
		$devotionList->{$args->{sourceID}}->{targetIDs}->{$ID} = $i;
		my $actor = Actor::get($ID);
		#FIXME: Need a better display
		$msg .= skillUseNoDamage_string($source, $actor, 0, 'devotion');
	}
	$devotionList->{$args->{sourceID}}->{range} = $args->{range};

	message "$msg", "devotion";
}

sub egg_list {
	my ($self, $args) = @_;
	message T("----- Egg Hatch Candidates -----\n"), "list";
	for (my $i = 4; $i < $args->{RAW_MSG_SIZE}; $i += 2) {
		my $index = unpack("v1", substr($args->{RAW_MSG}, $i, 2));
		my $item = $char->inventory->getByServerIndex($index);
		message "$item->{invIndex} $item->{name}\n", "list";
	}
	message "------------------------------\n", "list";
}

sub emoticon {
	my ($self, $args) = @_;
	my $emotion = $emotions_lut{$args->{type}}{display} || "<emotion #$args->{type}>";

	if ($args->{ID} eq $accountID) {
		message "$char->{name}: $emotion\n", "emotion";
		chatLog("e", "$char->{name}: $emotion\n") if (existsInList($config{'logEmoticons'}, $args->{type}) || $config{'logEmoticons'} eq "all");

	} elsif (my $player = $playersList->getByID($args->{ID})) {
		my $name = $player->name;

		#my $dist = "unknown";
		my $dist = distance($char->{pos_to}, $player->{pos_to});
		$dist = sprintf("%.1f", $dist) if ($dist =~ /\./);

		# Translation Comment: "[dist=$dist] $name ($player->{binID}): $emotion\n"
		message TF("[dist=%s] %s (%d): %s\n", $dist, $name, $player->{binID}, $emotion), "emotion";
		chatLog("e", "$name".": $emotion\n") if (existsInList($config{'logEmoticons'}, $args->{type}) || $config{'logEmoticons'} eq "all");

		my $index = AI::findAction("follow");
		if ($index ne "") {
			my $masterID = AI::args($index)->{ID};
			if ($config{'followEmotion'} && $masterID eq $args->{ID} &&
			       distance($char->{pos_to}, $player->{pos_to}) <= $config{'followEmotion_distance'})
			{
				my %args = ();
				$args{timeout} = time + rand (1) + 0.75;

				if ($args->{type} == 30) {
					$args{emotion} = 31;
				} elsif ($args->{type} == 31) {
					$args{emotion} = 30;
				} else {
					$args{emotion} = $args->{type};
				}

				AI::queue("sendEmotion", \%args);
			}
		}
	} elsif (my $monster = $monstersList->getByID($args->{ID}) || $slavesList->getByID($args->{ID})) {
		my $dist = distance($char->{pos_to}, $monster->{pos_to});
		$dist = sprintf("%.1f", $dist) if ($dist =~ /\./);

		# Translation Comment: "[dist=$dist] $monster->name ($monster->{binID}): $emotion\n"
		message TF("[dist=%s] %s %s (%d): %s\n", $dist, $monster->{actorType}, $monster->name, $monster->{binID}, $emotion), "emotion";

	} else {
		my $actor = Actor::get($args->{ID});
		my $name = $actor->name;

		my $dist = T("unknown");
		if (!$actor->isa('Actor::Unknown')) {
			$dist = distance($char->{pos_to}, $actor->{pos_to});
			$dist = sprintf("%.1f", $dist) if ($dist =~ /\./);
		}

		message TF("[dist=%s] %s: %s\n", $dist, $actor->nameIdx, $emotion), "emotion";
		chatLog("e", "$name".": $emotion\n") if (existsInList($config{'logEmoticons'}, $args->{type}) || $config{'logEmoticons'} eq "all");
	}
	Plugins::callHook('packet_emotion', {
		emotion => $emotion,
		ID => $args->{ID}
	});
}

sub equip_item {
	my ($self, $args) = @_;
	my $item = $char->inventory->getByServerIndex($args->{index});
	if (!$args->{success}) {
		message TF("You can't put on %s (%d)\n", $item->{name}, $item->{invIndex});
	} else {
		$item->{equipped} = $args->{type};
		if ($args->{type} == 10 || $args->{type} == 32768) {
			$char->{equipment}{arrow} = $item;
		} else {
			foreach (%equipSlot_rlut){
				if ($_ & $args->{type}){
					next if $_ == 10; # work around Arrow bug
					next if $_ == 32768;
					$char->{equipment}{$equipSlot_lut{$_}} = $item;
				}
			}
		}
		message TF("You equip %s (%d) - %s (type %s)\n", $item->{name}, $item->{invIndex},
			$equipTypes_lut{$item->{type_equip}}, $args->{type}), 'inventory';
	}
	$ai_v{temp}{waitForEquip}-- if $ai_v{temp}{waitForEquip};
}

sub errors {
	my ($self, $args) = @_;

	Plugins::callHook('disconnected') if ($net->getState() == Network::IN_GAME);
	if ($net->getState() == Network::IN_GAME &&
		($config{dcOnDisconnect} > 1 ||
		($config{dcOnDisconnect} &&
		$args->{type} != 3 &&
		$args->{type} != 10))) {
		message T("Lost connection; exiting\n");
		$quit = 1;
	}

	$net->setState(1);
	undef $conState_tries;

	$timeout_ex{'master'}{'time'} = time;
	$timeout_ex{'master'}{'timeout'} = $timeout{'reconnect'}{'timeout'};
	if (($args->{type} != 0)) {
		$net->serverDisconnect();
	}
	if ($args->{type} == 0) {
		# FIXME BAN_SERVER_SHUTDOWN is 0x1, 0x0 is BAN_UNFAIR
		error T("Server shutting down\n"), "connection";
		if($config{'dcOnServerShutDown'} == 1) {
			$quit = 1;
		}
	} elsif ($args->{type} == 1) {
		error T("Error: Server is closed\n"), "connection";
		if($config{'dcOnServerClose'} == 1) {
			$quit = 1;
		}
	} elsif ($args->{type} == 2) {
		if ($config{'dcOnDualLogin'} == 1) {
			$interface->errorDialog(TF("Critical Error: Dual login prohibited - Someone trying to login!\n\n" .
				"%s will now immediately 	disconnect.", $Settings::NAME));
			$quit = 1;
		} elsif ($config{'dcOnDualLogin'} >= 2) {
			error T("Critical Error: Dual login prohibited - Someone trying to login!\n"), "connection";
			message TF("Disconnect for %s seconds...\n", $config{'dcOnDualLogin'}), "connection";
			$timeout_ex{'master'}{'timeout'} = $config{'dcOnDualLogin'};
		} else {
			error T("Critical Error: Dual login prohibited - Someone trying to login!\n"), "connection";
		}

	} elsif ($args->{type} == 3) {
		error T("Error: Out of sync with server\n"), "connection";
	} elsif ($args->{type} == 4) {
		# fRO: "Your account is not validated, please click on the validation link in your registration mail."
		error T("Error: Server is jammed due to over-population.\n"), "connection";
	} elsif ($args->{type} == 5) {
		error T("Error: You are underaged and cannot join this server.\n"), "connection";
	} elsif ($args->{type} == 6) {
		$interface->errorDialog(T("Critical Error: You must pay to play this account!\n"));
		$quit = 1 unless ($net->version == 1);
	} elsif ($args->{type} == 8) {
		error T("Error: The server still recognizes your last connection\n"), "connection";
	} elsif ($args->{type} == 9) {
		error T("Error: IP capacity of this Internet Cafe is full. Would you like to pay the personal base?\n"), "connection";
	} elsif ($args->{type} == 10) {
		error T("Error: You are out of available time paid for\n"), "connection";
	} elsif ($args->{type} == 15) {
		error T("Error: You have been forced to disconnect by a GM\n"), "connection";
	} elsif ($args->{type} == 101) {
		error T("Error: Your account has been suspended until the next maintenance period for possible use of 3rd party programs\n"), "connection";
	} elsif ($args->{type} == 102) {
		error T("Error: For an hour, more than 10 connections having same IP address, have made. Please check this matter.\n"), "connection";
	} else {
		error TF("Unknown error %s\n", $args->{type}), "connection";
	}
}


sub inventory_items_stackable {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	$self->_items_list({
		class => 'Actor::Item',
		hook => 'packet_inventory',
		debug_str => 'Stackable Inventory Item',
		items => [$self->parse_items_stackable($args)],
		getter => sub { $char->inventory->getByServerIndex($_[0]{index}) },
		adder => sub { $char->inventory->add($_[0]) },
		callback => sub {
			my ($local_item) = @_;

			if (defined $char->{arrow} && $local_item->{index} == $char->{arrow}) {
				$local_item->{equipped} = 32768;
				$char->{equipment}{arrow} = $local_item;
			}
		}
	});

	$ai_v{'inventory_time'} = time + 1;
	$ai_v{'cart_time'} = time + 1;
}

sub item_appeared {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	my $item = $itemsList->getByID($args->{ID});
	my $mustAdd;
	if (!$item) {
		$item = new Actor::Item();
		$item->{appear_time} = time;
		$item->{amount} = $args->{amount};
		$item->{nameID} = $args->{nameID};
		$item->{identified} = $args->{identified};
		$item->{name} = itemName($item);
		$item->{ID} = $args->{ID};
		$mustAdd = 1;
	}
	$item->{pos}{x} = $args->{x};
	$item->{pos}{y} = $args->{y};
	$item->{pos_to}{x} = $args->{x};
	$item->{pos_to}{y} = $args->{y};
	$itemsList->add($item) if ($mustAdd);

	# Take item as fast as possible
	if ($AI == AI::AUTO && pickupitems(lc($item->{name})) == 2
	 && ($config{'itemsTakeAuto'} || $config{'itemsGatherAuto'})
	 && (percent_weight($char) < $config{'itemsMaxWeight'})
	 && distance($item->{pos}, $char->{pos_to}) <= 5) {
		$messageSender->sendTake($args->{ID});
	}

	message TF("Item Appeared: %s (%d) x %d (%d, %d)\n", $item->{name}, $item->{binID}, $item->{amount}, $args->{x}, $args->{y}), "drop", 1;

}

sub item_exists {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	my $item = $itemsList->getByID($args->{ID});
	my $mustAdd;
	if (!$item) {
		$item = new Actor::Item();
		$item->{appear_time} = time;
		$item->{amount} = $args->{amount};
		$item->{nameID} = $args->{nameID};
		$item->{ID} = $args->{ID};
		$item->{identified} = $args->{identified};
		$item->{name} = itemName($item);
		$mustAdd = 1;
	}
	$item->{pos}{x} = $args->{x};
	$item->{pos}{y} = $args->{y};
	$item->{pos_to}{x} = $args->{x};
	$item->{pos_to}{y} = $args->{y};
	$itemsList->add($item) if ($mustAdd);

	message TF("Item Exists: %s (%d) x %d\n", $item->{name}, $item->{binID}, $item->{amount}), "drop", 1;
}

sub item_disappeared {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	my $item = $itemsList->getByID($args->{ID});
	if ($item) {
		if ($config{attackLooters} && AI::action ne "sitAuto" && pickupitems(lc($item->{name})) > 0) {
			foreach my Actor::Monster $monster (@{$monstersList->getItems()}) { # attack looter code
				if (my $control = mon_control($monster->name,$monster->{nameID})) {
					next if ( ($control->{attack_auto}  ne "" && $control->{attack_auto} == -1)
						|| ($control->{attack_lvl}  ne "" && $control->{attack_lvl} > $char->{lv})
						|| ($control->{attack_jlvl} ne "" && $control->{attack_jlvl} > $char->{lv_job})
						|| ($control->{attack_hp}   ne "" && $control->{attack_hp} > $char->{hp})
						|| ($control->{attack_sp}   ne "" && $control->{attack_sp} > $char->{sp})
						);
				}
				if (distance($item->{pos}, $monster->{pos}) == 0) {
					attack($monster->{ID});
					message TF("Attack Looter: %s looted %s\n", $monster->nameIdx, $item->{name}), "looter";
					last;
				}
			}
		}

		debug "Item Disappeared: $item->{name} ($item->{binID})\n", "parseMsg_presence";
		my $ID = $args->{ID};
		$items_old{$ID} = $item->deepCopy();
		$items_old{$ID}{disappeared} = 1;
		$items_old{$ID}{gone_time} = time;
		$itemsList->removeByID($ID);
	}
}

sub item_skill {
	my ($self, $args) = @_;

	my $skillID = $args->{skillID};
	my $targetType = $args->{targetType}; # we don't use this yet
	my $skillLv = $args->{skillLv};
	my $sp = $args->{sp}; # we don't use this yet
	my $skillName = $args->{skillName};

	my $skill = new Skill(idn => $skillID, level => $skillLv);
	message TF("Permitted to use %s (%d), level %d\n", $skill->getName, $skill->getIDN, $skill->getLevel);

	unless ($config{noAutoSkill}) {
		$messageSender->sendSkillUse($skillID, $skillLv, $accountID);
		undef $char->{permitSkill};
	} else {
		$char->{permitSkill} = $skill;
	}

	Plugins::callHook('item_skill', {
		ID => $skillID,
		level => $skillLv,
		name => $skillName
	});
}

sub item_upgrade {
	my ($self, $args) = @_;
	my ($type, $index, $upgrade) = @{$args}{qw(type index upgrade)};

	my $item = $char->inventory->getByServerIndex($index);
	if ($item) {
		$item->{upgrade} = $upgrade;
		message TF("Item %s has been upgraded to +%s\n", $item->{name}, $upgrade), "parseMsg/upgrade";
		$item->setName(itemName($item));
	}
}

sub job_equipment_hair_change {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	my $actor = Actor::get($args->{ID});
	assert(UNIVERSAL::isa($actor, "Actor")) if DEBUG;

	if ($args->{part} == 0) {
		# Job change
		$actor->{jobID} = $args->{number};
 		message TF("%s changed job to: %s\n", $actor, $jobs_lut{$args->{number}}), "parseMsg/job", ($actor->isa('Actor::You') ? 0 : 2);

	} elsif ($args->{part} == 3) {
		# Bottom headgear change
 		message TF("%s changed bottom headgear to: %s\n", $actor, headgearName($args->{number})), "parseMsg_statuslook", 2 unless $actor->isa('Actor::You');
		$actor->{headgear}{low} = $args->{number} if ($actor->isa('Actor::Player') || $actor->isa('Actor::You'));

	} elsif ($args->{part} == 4) {
		# Top headgear change
 		message TF("%s changed top headgear to: %s\n", $actor, headgearName($args->{number})), "parseMsg_statuslook", 2 unless $actor->isa('Actor::You');
		$actor->{headgear}{top} = $args->{number} if ($actor->isa('Actor::Player') || $actor->isa('Actor::You'));

	} elsif ($args->{part} == 5) {
		# Middle headgear change
 		message TF("%s changed middle headgear to: %s\n", $actor, headgearName($args->{number})), "parseMsg_statuslook", 2 unless $actor->isa('Actor::You');
		$actor->{headgear}{mid} = $args->{number} if ($actor->isa('Actor::Player') || $actor->isa('Actor::You'));

	} elsif ($args->{part} == 6) {
		# Hair color change
		$actor->{hair_color} = $args->{number};
 		message TF("%s changed hair color to: %s (%s)\n", $actor, $haircolors{$args->{number}}, $args->{number}), "parseMsg/hairColor", ($actor->isa('Actor::You') ? 0 : 2);
	}

	#my %parts = (
	#	0 => 'Body',
	#	2 => 'Right Hand',
	#	3 => 'Low Head',
	#	4 => 'Top Head',
	#	5 => 'Middle Head',
	#	8 => 'Left Hand'
	#);
	#if ($part == 3) {
	#	$part = 'low';
	#} elsif ($part == 4) {
	#	$part = 'top';
	#} elsif ($part == 5) {
	#	$part = 'mid';
	#}
	#
	#my $name = getActorName($ID);
	#if ($part == 3 || $part == 4 || $part == 5) {
	#	my $actor = Actor::get($ID);
	#	$actor->{headgear}{$part} = $items_lut{$number} if ($actor);
	#	my $itemName = $items_lut{$itemID};
	#	$itemName = 'nothing' if (!$itemName);
	#	debug "$name changes $parts{$part} ($part) equipment to $itemName\n", "parseMsg";
	#} else {
	#	debug "$name changes $parts{$part} ($part) equipment to item #$number\n", "parseMsg";
	#}

}


# Leap, Snap, Back Slide... Various knockback
sub high_jump {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	my $actor = Actor::get ($args->{ID});
	if (!defined $actor) {
		$actor = new Actor::Unknown;
		$actor->{appear_time} = time;
		$actor->{nameID} = unpack ('V', $args->{ID});
	} elsif ($actor->{pos_to}{x} == $args->{x} && $actor->{pos_to}{y} == $args->{y}) {
		message TF("%s failed to instantly move\n", $actor->nameString), 'skill';
		return;
	}

	$actor->{pos} = {x => $args->{x}, y => $args->{y}};
	$actor->{pos_to} = {x => $args->{x}, y => $args->{y}};

	message TF("%s instantly moved to %d, %d\n", $actor->nameString, $actor->{pos_to}{x}, $actor->{pos_to}{y}), 'skill', 2;

	$actor->{time_move} = time;
	$actor->{time_move_calc} = 0;
}

sub hp_sp_changed {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	my $type = $args->{type};
	my $amount = $args->{amount};
	if ($type == 5) {
		$char->{hp} += $amount;
		$char->{hp} = $char->{hp_max} if ($char->{hp} > $char->{hp_max});
	} elsif ($type == 7) {
		$char->{sp} += $amount;
		$char->{sp} = $char->{sp_max} if ($char->{sp} > $char->{sp_max});
	}
}

sub login_error {
	my ($self, $args) = @_;

	$net->serverDisconnect();
	if ($args->{type} == REFUSE_INVALID_ID) {
		error TF("Account name [%s] doesn't exist\n", $config{'username'}), "connection";
		if (!$net->clientAlive() && !$config{'ignoreInvalidLogin'} && !UNIVERSAL::isa($net, 'Network::XKoreProxy')) {
			my $username = $interface->query(T("Enter your Ragnarok Online username again."));
			if (defined($username)) {
				configModify('username', $username, 1);
				$timeout_ex{master}{time} = 0;
				$conState_tries = 0;
			} else {
				quit();
				return;
			}
		}
	} elsif ($args->{type} == REFUSE_INVALID_PASSWD) {
		error TF("Password Error for account [%s]\n", $config{'username'}), "connection";
		if (!$net->clientAlive() && !$config{'ignoreInvalidLogin'} && !UNIVERSAL::isa($net, 'Network::XKoreProxy')) {
			my $password = $interface->query(T("Enter your Ragnarok Online password again."), isPassword => 1);
			if (defined($password)) {
				configModify('password', $password, 1);
				$timeout_ex{master}{time} = 0;
				$conState_tries = 0;
			} else {
				quit();
				return;
			}
		}
	} elsif ($args->{type} == ACCEPT_ID_PASSWD) {
		error T("The server has denied your connection.\n"), "connection";
	} elsif ($args->{type} == REFUSE_NOT_CONFIRMED) {
		error T("Server unavailable.\n"), "connection";
	} elsif ($args->{type} == REFUSE_INVALID_VERSION) {
		my $master = $masterServer;
		error TF("Connect failed, something is wrong with the login settings:\n" .
			"version: %s\n" .
			"master_version: %s\n" .
			"serverType: %s\n", $master->{version}, $master->{master_version}, $masterServer->{serverType}), "connection";
		relog(30);
	} elsif ($args->{type} == REFUSE_BLOCK_TEMPORARY) {
		error TF("The server is temporarily blocking your connection until %s\n", $args->{date}), "connection";
	} elsif ($args->{type} == REFUSE_USER_PHONE_BLOCK) { #Phone lock
		error T("Please dial to activate the login procedure.\n"), "connection";
		Plugins::callHook('dial');
		relog(10);
	} elsif ($args->{type} == ACCEPT_LOGIN_USER_PHONE_BLOCK) {
		error T("Mobile Authentication: Max number of simultaneous IP addresses reached.\n"), "connection";
	} else {
		error TF("The server has denied your connection for unknown reason (%d).\n", $args->{type}), 'connection';
	}

	if ($args->{type} != REFUSE_INVALID_VERSION && $versionSearch) {
		$versionSearch = 0;
		writeSectionedFileIntact(Settings::getTableFilename("servers.txt"), \%masterServers);
	}
}

sub login_error_game_login_server {
	error T("Error logging into Character Server (invalid character specified)...\n"), 'connection';
	$net->setState(1);
	undef $conState_tries;
	$timeout_ex{master}{time} = time;
	$timeout_ex{master}{timeout} = $timeout{'reconnect'}{'timeout'};
	$net->serverDisconnect();
}

# The difference between map_change and map_changed is that map_change
# represents a map change event on the current map server, while
# map_changed means that you've changed to a different map server.
# map_change also represents teleport events.
sub map_change {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	my $oldMap = $field ? $field->baseName : undef; # Get old Map name without InstanceID
	my ($map) = $args->{map} =~ /([\s\S]*)\./;
	my $map_noinstance;
	($map_noinstance, undef) = Field::nameToBaseName(undef, $map); # Hack to clean up InstanceID

	checkAllowedMap($map_noinstance);
	if (!$field || $map ne $field->name()) {
		eval {
			$field = new Field(name => $map);
		};
		if (my $e = caught('FileNotFoundException', 'IOException')) {
			error TF("Cannot load field %s: %s\n", $map_noinstance, $e);
			undef $field;
		} elsif ($@) {
			die $@;
		}
	}

	if ($ai_v{temp}{clear_aiQueue}) {
		AI::clear;
		AI::SlaveManager::clear();
	}

	main::initMapChangeVars();
	for (my $i = 0; $i < @ai_seq; $i++) {
		ai_setMapChanged($i);
	}
	AI::SlaveManager::setMapChanged ();
	if ($net->version == 0) {
		$ai_v{portalTrace_mapChanged} = time;
	}

	my %coords = (
		x => $args->{x},
		y => $args->{y}
	);
	$char->{pos} = {%coords};
	$char->{pos_to} = {%coords};
	message TF("Map Change: %s (%s, %s)\n", $args->{map}, $char->{pos}{x}, $char->{pos}{y}), "connection";
	if ($net->version == 1) {
		ai_clientSuspend(0, 10);
	} else {
		$messageSender->sendMapLoaded();
		# $messageSender->sendSync(1);
		$timeout{ai}{time} = time;
	}

	Plugins::callHook('Network::Receive::map_changed', {
		oldMap => $oldMap,
	});

	$timeout{ai}{time} = time;
}

sub map_changed {
	my ($self, $args) = @_;
	$net->setState(4);

	my $oldMap = $field ? $field->baseName : undef; # Get old Map name without InstanceID
	my ($map) = $args->{map} =~ /([\s\S]*)\./;
	my $map_noinstance;
	($map_noinstance, undef) = Field::nameToBaseName(undef, $map); # Hack to clean up InstanceID

	checkAllowedMap($map_noinstance);
	if (!$field || $map ne $field->name()) {
		eval {
			$field = new Field(name => $map);
		};
		if (my $e = caught('FileNotFoundException', 'IOException')) {
			error TF("Cannot load field %s: %s\n", $map_noinstance, $e);
			undef $field;
		} elsif ($@) {
			die $@;
		}
	}

	my %coords = (
		x => $args->{x},
		y => $args->{y}
	);
	$char->{pos} = {%coords};
	$char->{pos_to} = {%coords};

	undef $conState_tries;
	for (my $i = 0; $i < @ai_seq; $i++) {
		ai_setMapChanged($i);
	}
	AI::SlaveManager::setMapChanged ();
	$ai_v{portalTrace_mapChanged} = time;

	$map_ip = makeIP($args->{IP});
	$map_port = $args->{port};
	message(swrite(
		"---------Map  Info----------", [],
		"MAP Name: @<<<<<<<<<<<<<<<<<<",
		[$args->{map}],
		"MAP IP: @<<<<<<<<<<<<<<<<<<",
		[$map_ip],
		"MAP Port: @<<<<<<<<<<<<<<<<<<",
		[$map_port],
		"-------------------------------", []),
		"connection");

	message T("Closing connection to Map Server\n"), "connection";
	$net->serverDisconnect unless ($net->version == 1);

	# Reset item and skill times. The effect of items (like aspd potions)
	# and skills (like Twohand Quicken) disappears when we change map server.
	# NOTE: with the newer servers, this isn't true anymore
	my $i = 0;
	while (exists $config{"useSelf_item_$i"}) {
		if (!$config{"useSelf_item_$i"}) {
			$i++;
			next;
		}

		$ai_v{"useSelf_item_$i"."_time"} = 0;
		$i++;
	}
	$i = 0;
	while (exists $config{"useSelf_skill_$i"}) {
		if (!$config{"useSelf_skill_$i"}) {
			$i++;
			next;
		}

		$ai_v{"useSelf_skill_$i"."_time"} = 0;
		$i++;
	}
	$i = 0;
	while (exists $config{"doCommand_$i"}) {
		if (!$config{"doCommand_$i"}) {
			$i++;
			next;
		}

		$ai_v{"doCommand_$i"."_time"} = 0;
		$i++;
	}
	if ($char) {
		delete $char->{statuses};
		$char->{spirits} = 0;
		delete $char->{permitSkill};
		delete $char->{encoreSkill};
	}
	$cart{exists} = 0;
	undef %guild;

	Plugins::callHook('Network::Receive::map_changed', {
		oldMap => $oldMap,
	});
	$timeout{ai}{time} = time;
}

# +message_string
sub mercenary_off {
	$slavesList->removeByID($char->{mercenary}{ID});
	delete $char->{slaves}{$char->{mercenary}{ID}};
	delete $char->{mercenary};
}
# -message_string

sub memo_success {
	my ($self, $args) = @_;
	if ($args->{fail}) {
		warning T("Memo Failed\n");
	} else {
		message T("Memo Succeeded\n"), "success";
	}
}

# not only for mercenaries, this is an all purpose packet !
sub message_string {
	my ($self, $args) = @_;

	if ($msgTable[++$args->{msg_id}]) { # show message from msgstringtable.txt
		warning "$msgTable[$args->{msg_id}]\n";
		$self->mercenary_off() if ($args->{msg_id} >= 1267 && $args->{msg_id} <= 1270);
	} else {
		warning TF("Unknown message_string: %s. Need to update the file msgstringtable.txt (from data.grf)\n", $args->{msg_id});
	}
}

sub monster_typechange {
	my ($self, $args) = @_;

	# Class change / monster type change
	# 01B0 : long ID, byte WhateverThisIs, long type
	my $ID = $args->{ID};
	my $type = $args->{type};
	my $monster = $monstersList->getByID($ID);
	if ($monster) {
		my $oldName = $monster->name;
		if ($monsters_lut{$type}) {
			$monster->setName($monsters_lut{$type});
		} else {
			$monster->setName(undef);
		}
		$monster->{nameID} = $type;
		$monster->{dmgToParty} = 0;
		$monster->{dmgFromParty} = 0;
		$monster->{missedToParty} = 0;
		message TF("Monster %s (%d) changed to %s\n", $oldName, $monster->{binID}, $monster->name);
	}
}

sub monster_ranged_attack {
	my ($self, $args) = @_;

	my $ID = $args->{ID};
	my $range = $args->{range};

	my %coords1;
	$coords1{x} = $args->{sourceX};
	$coords1{y} = $args->{sourceY};
	my %coords2;
	$coords2{x} = $args->{targetX};
	$coords2{y} = $args->{targetY};

	my $monster = $monstersList->getByID($ID);
	$monster->{pos_attack_info} = {%coords1} if ($monster);
	$char->{pos} = {%coords2};
	$char->{pos_to} = {%coords2};
	debug "Received attack location - monster: $coords1{x},$coords1{y} - " .
		"you: $coords2{x},$coords2{y}\n", "parseMsg_move", 2;
}

sub mvp_item {
	my ($self, $args) = @_;
	my $display = itemNameSimple($args->{itemID});
	message TF("Get MVP item %s\n", $display);
	chatLog("k", TF("Get MVP item %s\n", $display));
}

sub mvp_other {
	my ($self, $args) = @_;
	my $display = Actor::get($args->{ID});
	message TF("%s become MVP!\n", $display);
	chatLog("k", TF("%s become MVP!\n", $display));
}

sub mvp_you {
	my ($self, $args) = @_;
	my $msg = TF("Congratulations, you are the MVP! Your reward is %s exp!\n", $args->{expAmount});
	message $msg;
	chatLog("k", $msg);
}

sub npc_image {
	my ($self, $args) = @_;
	my ($imageName) = bytesToString($args->{npc_image});
	if ($args->{type} == 2) {
		debug "Show NPC image: $imageName\n", "parseMsg";
	} elsif ($args->{type} == 255) {
		debug "Hide NPC image: $imageName\n", "parseMsg";
	} else {
		debug "NPC image: $imageName ($args->{type})\n", "parseMsg";
	}
}

sub npc_sell_list {
	my ($self, $args) = @_;
	#sell list, similar to buy list
	if (length($args->{RAW_MSG}) > 4) {
		my $newmsg;
		$self->decrypt(\$newmsg, substr($args->{RAW_MSG}, 4));
		my $msg = substr($args->{RAW_MSG}, 0, 4).$newmsg;
	}
	
	debug T("You can sell:\n"), "info";
	for (my $i = 0; $i < length($args->{itemsdata}); $i += 10) {
		my ($index, $price, $price_overcharge) = unpack("v L L", substr($args->{itemsdata},$i,($i + 10)));
		my $item = $char->inventory->getByServerIndex($index);
		# flag this item as sellable
		unless (exists $items_sellable{$item->{nameID}}) {
			$items_sellable{$item->{nameID}} = 1;
			updateItemsSellTable(Settings::getTableFilename("itemssellable.txt"), $item->{nameID}, 1);
		}
		debug TF("[%s x %s] for %sz each. \n", $item->{amount}, $item->{name}, $price_overcharge), "info";
	}
	
	# FIXME: http://forums.openkore.com/viewtopic.php?f=36&t=18076#p238614
	foreach my $item (@{$char->inventory->getItems()}) {
		next if ($item->{equipped} || $items_sellable{$item->{nameID}});
		# flag this item as unsellable
		unless (exists $items_sellable{$item->{nameID}}) {
			$items_sellable{$item->{nameID}} = 0;
			updateItemsSellTable(Settings::getTableFilename("itemssellable.txt"), $item->{nameID}, 0);
		}
	}
	
	undef $talk{buyOrSell};
	message T("Ready to start selling items\n");

	# continue talk sequence now
	$ai_v{npc_talk}{time} = Time::HiRes::time;
}

sub npc_store_begin {
	my ($self, $args) = @_;
	undef %talk;
	$talk{buyOrSell} = 1;
	$talk{ID} = $args->{ID};
	$ai_v{npc_talk}{talk} = 'buy';
	$ai_v{npc_talk}{time} = Time::HiRes::time;

	my $name = getNPCName($args->{ID});

	message TF("%s: Type 'store' to start buying, or type 'sell' to start selling\n", $name), "npc";
}

sub npc_store_info {
	my ($self, $args) = @_;
	my $newmsg;
	$self->decrypt(\$newmsg, substr($args->{RAW_MSG}, 4));
	my $msg = substr($args->{RAW_MSG}, 0, 4).$newmsg;
	undef @storeList;
	my $storeList = 0;
	undef $talk{'buyOrSell'};
	for (my $i = 4; $i < $args->{RAW_MSG_SIZE}; $i += 11) {
		my $price = unpack("V1", substr($msg, $i, 4));
		my $type = unpack("C1", substr($msg, $i + 8, 1));
		my $ID = unpack("v1", substr($msg, $i + 9, 2));

		my $store = $storeList[$storeList] = {};
		# TODO: use itemName() or itemNameSimple()?
		my $display = ($items_lut{$ID} ne "")
			? $items_lut{$ID}
			: "Unknown ".$ID;
		$store->{name} = $display;
		$store->{nameID} = $ID;
		$store->{type} = $type;
		$store->{price} = $price;
		debug "Item added to Store: $store->{name} - $price z\n", "parseMsg", 2;
		$storeList++;
	}

	# Real RO client can be receive this message without NPC Information. We should mimic this behavior.
	my $name = (defined $talk{ID}) ? getNPCName($talk{ID}) : 'Unknown';

	$ai_v{npc_talk}{talk} = 'store';
	# continue talk sequence now
	$ai_v{'npc_talk'}{'time'} = time;

	if (AI::action ne 'buyAuto') {
		message TF("----------%s's Store List-----------\n" .
			"#  Name                    Type               Price\n", $name), "list";
		my $display;
		for (my $i = 0; $i < @storeList; $i++) {
			$display = $storeList[$i]{'name'};
			message(swrite(
				"@< @<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<< @>>>>>>>z",
				[$i, $display, $itemTypes_lut{$storeList[$i]{'type'}}, $storeList[$i]{'price'}]),
				"list");
		}
		message("-------------------------------\n", "list");
	}
}

sub npc_talk {
	my ($self, $args) = @_;

	$talk{ID} = $args->{ID};
	$talk{nameID} = unpack 'V', $args->{ID};
	$talk{msg} = bytesToString ($args->{msg});

=pod
	my $newmsg;
	$self->decrypt(\$newmsg, substr($args->{RAW_MSG}, 8));

	my $msg = substr($args->{RAW_MSG}, 0, 8) . $newmsg;
	my $ID = substr($msg, 4, 4);
	my $talkMsg = unpack("Z*", substr($msg, 8));
	$talk{ID} = $ID;
	$talk{nameID} = unpack("V1", $ID);
	$talk{msg} = bytesToString($talkMsg);
=cut

	# Remove RO color codes
	$talk{msg} =~ s/\^[a-fA-F0-9]{6}//g;

	$ai_v{npc_talk}{talk} = 'initiated';
	$ai_v{npc_talk}{time} = Time::HiRes::time;

	my $name = getNPCName($talk{ID});
	Plugins::callHook('npc_talk', {
						ID => $talk{ID},
						nameID => $talk{nameID},
						name => $name,
						msg => $talk{msg},
						});
	message "$name: $talk{msg}\n", "npc";
}

sub npc_talk_close {
	my ($self, $args) = @_;
	# 00b6: long ID
	# "Close" icon appreared on the NPC message dialog
	my $ID = $args->{ID};
	my $name = getNPCName($ID);

	message TF("%s: Done talking\n", $name), "npc";

	# I noticed that the RO client doesn't send a 'talk cancel' packet
	# when it receives a 'npc_talk_closed' packet from the server'.
	# But on pRO Thor (with Kapra password) this is required in order to
	# open the storage.
	#
	# UPDATE: not sending 'talk cancel' breaks autostorage on iRO.
	# This needs more investigation.
	if (!$talk{canceled}) {
		$messageSender->sendTalkCancel($ID);
	}

	$ai_v{npc_talk}{talk} = 'close';
	$ai_v{npc_talk}{time} = Time::HiRes::time;
	undef %talk;

	Plugins::callHook('npc_talk_done', {ID => $ID});
}

sub npc_talk_continue {
	my ($self, $args) = @_;
	my $ID = substr($args->{RAW_MSG}, 2, 4);
	my $name = getNPCName($ID);

	$ai_v{npc_talk}{talk} = 'next';
	$ai_v{npc_talk}{time} = Time::HiRes::time;

	if ($config{autoTalkCont}) {
		message TF("%s: Auto-continuing talking\n", $name), "npc";
		$messageSender->sendTalkContinue($ID);
		# This time will be reset once the NPC responds
		$ai_v{npc_talk}{time} = time + $timeout{'ai_npcTalk'}{'timeout'} + 5;
	} else {
		message TF("%s: Type 'talk cont' to continue talking\n", $name), "npc";
	}
}

sub npc_talk_number {
	my ($self, $args) = @_;

	my $ID = $args->{ID};

	my $name = getNPCName($ID);
	$ai_v{npc_talk}{talk} = 'number';
	$ai_v{npc_talk}{time} = Time::HiRes::time;

	message TF("%s: Type 'talk num <number #>' to input a number.\n", $name), "input";
	$ai_v{'npc_talk'}{'talk'} = 'num';
	$ai_v{'npc_talk'}{'time'} = time;
}

sub npc_talk_responses {
	my ($self, $args) = @_;
	# 00b7: word len, long ID, string str
	# A list of selections appeared on the NPC message dialog.
	# Each item is divided with ':'
	my $newmsg;
	$self->decrypt(\$newmsg, substr($args->{RAW_MSG}, 8));
	my $msg = substr($args->{RAW_MSG}, 0, 8).$newmsg;

	my $ID = substr($msg, 4, 4);
	$talk{ID} = $ID;
	my $talk = unpack("Z*", substr($msg, 8));
	$talk = substr($msg, 8) if (!defined $talk);
	$talk = bytesToString($talk);

	my @preTalkResponses = split /:/, $talk;
	$talk{responses} = [];
	foreach my $response (@preTalkResponses) {
		# Remove RO color codes
		$response =~ s/\^[a-fA-F0-9]{6}//g;
		if ($response =~ /^\^nItemID\^(\d+)$/) {
			$response = itemNameSimple($1);
		}

		push @{$talk{responses}}, $response if ($response ne "");
	}

	$talk{responses}[@{$talk{responses}}] = T("Cancel Chat");

	$ai_v{'npc_talk'}{'talk'} = 'select';
	$ai_v{'npc_talk'}{'time'} = time;

	my $list = T("----------Responses-----------\n" .
		"#  Response\n");
	for (my $i = 0; $i < @{$talk{responses}}; $i++) {
		$list .= swrite(
			"@< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<",
			[$i, $talk{responses}[$i]]);
	}
	$list .= "-------------------------------\n";
	message($list, "list");
	my $name = getNPCName($ID);
	Plugins::callHook('npc_talk_responses', {
						ID => $ID,
						name => $name,
						responses => $talk{responses},
						});
	message TF("%s: Type 'talk resp #' to choose a response.\n", $name), "npc";
}

sub npc_talk_text {
	my ($self, $args) = @_;

	my $ID = $args->{ID};

	my $name = getNPCName($ID);
	message TF("%s: Type 'talk text' (Respond to NPC)\n", $name), "npc";
	$ai_v{npc_talk}{talk} = 'text';
	$ai_v{npc_talk}{time} = Time::HiRes::time;
}

# TODO: store this state
sub party_allow_invite {
   my ($self, $args) = @_;

   if ($args->{type}) {
      message T("Not allowed other player invite to Party\n"), "party", 1;
   } else {
      message T("Allowed other player invite to Party\n"), "party", 1;
   }
}

sub party_chat {
	my ($self, $args) = @_;
	my $msg;

	$self->decrypt(\$msg, $args->{message});
	$msg = bytesToString($msg);

	# Type: String
	my ($chatMsgUser, $chatMsg) = $msg =~ /(.*?) : (.*)/;
	$chatMsgUser =~ s/ $//;

	stripLanguageCode(\$chatMsg);
	# Type: String
	my $chat = "$chatMsgUser : $chatMsg";
	message TF("[Party] %s\n", $chat), "partychat";

	chatLog("p", "$chat\n") if ($config{'logPartyChat'});
	ChatQueue::add('p', $args->{ID}, $chatMsgUser, $chatMsg);

	Plugins::callHook('packet_partyMsg', {
		MsgUser => $chatMsgUser,
		Msg => $chatMsg
	});
}

# TODO: itemPickup itemDivision
sub party_exp {
	my ($self, $args) = @_;
	$char->{party}{share} = $args->{type}; # backwards compatible
	$char->{party}{sharing}{exp} = defined $args->{type} ? $args->{type} : -1;
	$char->{party}{sharing}{item}{pickup} = defined $args->{itemPickup} ? $args->{itemPickup} : -1;
	$char->{party}{sharing}{item}{division} = defined $args->{itemDivision} ? $args->{itemDivision} : -1;
	my %options = (
		-1 => T("unknown"),
		0 => T("individual"),
		1 => T("even")
	);
	message TF("Party sharing: %s exp, %s item pickup, %s item division\n",
			$options{$char->{party}{sharing}{exp}},
			$options{$char->{party}{sharing}{item}{pickup}},
			$options{$char->{party}{sharing}{item}{division}}
		), "party", 1;
}

sub party_hp_info {
	my ($self, $args) = @_;
	my $ID = $args->{ID};

	if ($char->{party}{users}{$ID}) {
		$char->{party}{users}{$ID}{hp} = $args->{hp};
		$char->{party}{users}{$ID}{hp_max} = $args->{hp_max};
	}
}

sub party_invite {
	my ($self, $args) = @_;
	message TF("Incoming Request to join party '%s'\n", bytesToString($args->{name}));
	$incomingParty{ID} = $args->{ID};
	$incomingParty{ACK} = $args->{switch} eq '02C6' ? '02C7' : '00FF';
	$timeout{ai_partyAutoDeny}{time} = time;
}

use constant {
  ANSWER_ALREADY_OTHERGROUPM => 0x0,
  ANSWER_JOIN_REFUSE => 0x1,
  ANSWER_JOIN_ACCEPT => 0x2,
  ANSWER_MEMBER_OVERSIZE => 0x3,
  ANSWER_DUPLICATE => 0x4,
  ANSWER_JOINMSG_REFUSE => 0x5,
  ANSWER_UNKNOWN_ERROR => 0x6,
  ANSWER_UNKNOWN_CHARACTER => 0x7,
  ANSWER_INVALID_MAPPROPERTY => 0x8,
};

sub party_invite_result {
	my ($self, $args) = @_;
	my $name = bytesToString($args->{name});
	if ($args->{type} == ANSWER_ALREADY_OTHERGROUPM) {
		warning TF("Join request failed: %s is already in a party\n", $name);
	} elsif ($args->{type} == ANSWER_JOIN_REFUSE) {
		warning TF("Join request failed: %s denied request\n", $name);
	} elsif ($args->{type} == ANSWER_JOIN_ACCEPT) {
		message TF("%s accepted your request\n", $name), "info";
	} elsif ($args->{type} == ANSWER_MEMBER_OVERSIZE) {
		message T("Join request failed: Party is full.\n"), "info";
	} elsif ($args->{type} == ANSWER_DUPLICATE) {
		message TF("Join request failed: same account of %s allready joined the party.\n", $name), "info";
	} elsif ($args->{type} == ANSWER_JOINMSG_REFUSE) {
		message TF("Join request failed: ANSWER_JOINMSG_REFUSE.\n", $name), "info";
	} elsif ($args->{type} == ANSWER_UNKNOWN_ERROR) {
		message TF("Join request failed: unknown error.\n", $name), "info";
	} elsif ($args->{type} == ANSWER_UNKNOWN_CHARACTER) {
		message TF("Join request failed: the character is not currently online or does not exist.\n", $name), "info";
	} elsif ($args->{type} == ANSWER_INVALID_MAPPROPERTY) {
		message TF("Join request failed: ANSWER_INVALID_MAPPROPERTY.\n", $name), "info";
	}
}

use constant {
	GROUPMEMBER_DELETE_LEAVE => 0x0,
	GROUPMEMBER_DELETE_EXPEL => 0x1,
};

sub party_leave {
	my ($self, $args) = @_;

	my $ID = $args->{ID};
	my $actor = $char->{party}{users}{$ID}; # bytesToString($args->{name})
	delete $char->{party}{users}{$ID};
	binRemove(\@partyUsersID, $ID);
	if ($ID eq $accountID) {
		$actor = $char;
		delete $char->{party};
		undef @partyUsersID;
	}

	if ($args->{result} == GROUPMEMBER_DELETE_LEAVE) {
		message TF("%s left the party\n", $actor);
	} elsif ($args->{result} == GROUPMEMBER_DELETE_EXPEL) {
		message TF("%s left the party (kicked)\n", $actor);
	} else {
		message TF("%s left the party (unknown reason: %d)\n", $actor, $args->{result});
	}
}

sub party_organize_result {
	my ($self, $args) = @_;

	unless ($args->{fail}) {
		$char->{party}{users}{$accountID}{admin} = 1 if $char->{party}{users}{$accountID};
	} elsif ($args->{fail} == 1) {
		warning T("Can't organize party - party name exists\n");
	} elsif ($args->{fail} == 2) {
		warning T("Can't organize party - you are already in a party\n");
	} elsif ($args->{fail} == 3) {
		warning T("Can't organize party - not allowed in current map\n");
	} else {
		warning TF("Can't organize party - unknown (%d)\n", $args->{fail});
	}
}

sub party_users_info {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	my $msg;
	$self->decrypt(\$msg, substr($args->{RAW_MSG}, 28));
	$msg = substr($args->{RAW_MSG}, 0, 28).$msg;
	$char->{party}{name} = bytesToString($args->{party_name});

	for (my $i = 28; $i < $args->{RAW_MSG_SIZE}; $i += 46) {
		my $ID = substr($msg, $i, 4);
		if (binFind(\@partyUsersID, $ID) eq "") {
			binAdd(\@partyUsersID, $ID);
		}
		$char->{party}{users}{$ID} = new Actor::Party();
		$char->{party}{users}{$ID}{name} = bytesToString(unpack("Z24", substr($msg, $i + 4, 24)));
		$char->{party}{users}{$ID}{map} = unpack("Z16", substr($msg, $i + 28, 16));
		$char->{party}{users}{$ID}{admin} = !(unpack("C1", substr($msg, $i + 44, 1)));
		$char->{party}{users}{$ID}{online} = !(unpack("C1",substr($msg, $i + 45, 1)));
		$char->{party}{users}{$ID}->{ID} = $ID;
		debug TF("Party Member: %s (%s)\n", $char->{party}{users}{$ID}{name}, $char->{party}{users}{$ID}{map}), "party", 1;
	}
	if (
			(
				(($config{partyAutoShare} || 0) != $char->{party}{sharing}{exp})
				|| (($config{partyAutoShareItem} || 0) != $char->{party}{sharing}{item}{pickup})
				|| (($config{partyAutoShareItemDiv} || 0) != $char->{party}{sharing}{item}{division})
			) && $char->{party} && %{$char->{party}} && $char->{party}{users}{$accountID}{admin}) {
		$messageSender->sendPartyOption($config{partyAutoShare}, $config{partyAutoShareItem}, $config{partyAutoShareItemDiv});
	}
}

sub forge_list {
	my ($self, $args) = @_;

	message T("========Forge List========\n");
	for (my $i = 4; $i < $args->{RAW_MSG_SIZE}; $i += 8) {
		my $viewID = unpack("v1", substr($args->{RAW_MSG}, $i, 2));
		message "$viewID $items_lut{$viewID}\n";
		# always 0x0012
		#my $unknown = unpack("v1", substr($args->{RAW_MSG}, $i+2, 2));
		# ???
		#my $charID = substr($args->{RAW_MSG}, $i+4, 4);
	}
	message "=========================\n";
	if ($config{autoCreate}) {
		# todo: implement extra items
		# todo: check if item is available
		my $item = $config{autoCreate};
		if ($item !~ /^\d+$/) {
			# transform itemName into itemID
			$item = itemNameToID($item);
			if (!$item) {
				error TF("Invalid item in autoCreate config key \n");
				return;
			}
		}
		$messageSender->sendProduceMix($item, 0, 0, 0);
	}
}

sub friend_list {
	my ($self, $args) = @_;

	# Friend list
	undef @friendsID;
	undef %friends;
	my $msg = $args->{RAW_MSG};
	my $msg_size = $args->{RAW_MSG_SIZE};

	my $ID = 0;
	for (my $i = 4; $i < $msg_size; $i += 32) {
		binAdd(\@friendsID, $ID);
		$friends{$ID}{'accountID'} = substr($msg, $i, 4);
		$friends{$ID}{'charID'} = substr($msg, $i + 4, 4);
		$friends{$ID}{'name'} = bytesToString(unpack("Z24", substr($msg, $i + 8 , 24)));
		$friends{$ID}{'online'} = 0;
		$ID++;
	}
}

sub friend_logon {
	my ($self, $args) = @_;

	# Friend In/Out
	my $friendAccountID = $args->{friendAccountID};
	my $friendCharID = $args->{friendCharID};
	my $isNotOnline = $args->{isNotOnline};

	for (my $i = 0; $i < @friendsID; $i++) {
		if ($friends{$i}{'accountID'} eq $friendAccountID && $friends{$i}{'charID'} eq $friendCharID) {
			$friends{$i}{'online'} = 1 - $isNotOnline;
			if ($isNotOnline) {
				message TF("Friend %s has disconnected\n", $friends{$i}{name}), undef, 1;
			} else {
				message TF("Friend %s has connected\n", $friends{$i}{name}), undef, 1;
			}
			last;
		}
	}
}

sub friend_request {
	my ($self, $args) = @_;

	# Incoming friend request
	$incomingFriend{'accountID'} = $args->{accountID};
	$incomingFriend{'charID'} = $args->{charID};
	$incomingFriend{'name'} = bytesToString($args->{name});
	message TF("%s wants to be your friend\n", $incomingFriend{'name'});
	message TF("Type 'friend accept' to be friend with %s, otherwise type 'friend reject'\n", $incomingFriend{'name'});
}

sub friend_removed {
	my ($self, $args) = @_;

	# Friend removed
	my $friendAccountID =  $args->{friendAccountID};
	my $friendCharID =  $args->{friendCharID};
	for (my $i = 0; $i < @friendsID; $i++) {
		if ($friends{$i}{'accountID'} eq $friendAccountID && $friends{$i}{'charID'} eq $friendCharID) {
			message TF("%s is no longer your friend\n", $friends{$i}{'name'});
			binRemove(\@friendsID, $i);
			delete $friends{$i};
			last;
		}
	}
}

sub friend_response {
	my ($self, $args) = @_;

	# Response to friend request
	my $type = $args->{type};
	my $name = bytesToString($args->{name});
	if ($type) {
		message TF("%s rejected to be your friend\n", $name);
	} else {
		my $ID = @friendsID;
		binAdd(\@friendsID, $ID);
		$friends{$ID}{accountID} = substr($args->{RAW_MSG}, 4, 4);
		$friends{$ID}{charID} = substr($args->{RAW_MSG}, 8, 4);
		$friends{$ID}{name} = $name;
		$friends{$ID}{online} = 1;
		message TF("%s is now your friend\n", $name);
	}
}

sub homunculus_food {
	my ($self, $args) = @_;
	if ($args->{success}) {
		message TF("Fed homunculus with %s\n", itemNameSimple($args->{foodID})), "homunculus";
	} else {
		error TF("Failed to feed homunculus with %s: no food in inventory.\n", itemNameSimple($args->{foodID})), "homunculus";
		# auto-vaporize
		if ($char->{homunculus} && $char->{homunculus}{hunger} <= 11 && timeOut($char->{homunculus}{vaporize_time}, 5)) {
			$messageSender->sendSkillUse(244, 1, $accountID);
			$char->{homunculus}{vaporize_time} = time;
			error "Critical hunger level reached. Homunculus is put to rest.\n", "homunculus";
		}
	}
}

sub homunculus_state_handler {
	my ($slave, $args) = @_;
	# Homunculus states:
	# 0 - alive and unnamed
	# 2 - rest
	# 4 - dead

	return unless $char->{homunculus};

	if ($args->{state} == 0) {
		$char->{homunculus}{renameflag} = 1;
	} else {
		$char->{homunculus}{renameflag} = 0;
	}

	if (($args->{state} & ~8) > 1) {
		foreach my $handle (@{$char->{homunculus}{slave_skillsID}}) {
			delete $char->{skills}{$handle};
		}
		$char->{homunculus}->clear();
		undef @{$char->{homunculus}{slave_skillsID}};
		if (defined $slave->{state} && $slave->{state} != $args->{state}) {
			if ($args->{state} & 2) {
				message T("Your Homunculus was vaporized!\n"), 'homunculus';
			} elsif ($args->{state} & 4) {
				message T("Your Homunculus died!\n"), 'homunculus';
			}
		}
	} elsif (defined $slave->{state} && $slave->{state} != $args->{state}) {
		if ($slave->{state} & 2) {
			message T("Your Homunculus was recalled!\n"), 'homunculus';
		} elsif ($slave->{state} & 4) {
			message T("Your Homunculus was resurrected!\n"), 'homunculus';
		}
	}
}

sub gameguard_grant {
	my ($self, $args) = @_;

	if ($args->{server} == 0) {
		error T("The server Denied the login because GameGuard packets where not replied " .
			"correctly or too many time has been spent to send the response.\n" .
			"Please verify the version of your poseidon server and try again\n"), "poseidon";
		return;
	} elsif ($args->{server} == 1) {
		message T("Server granted login request to account server\n"), "poseidon";
	} else {
		message T("Server granted login request to char/map server\n"), "poseidon";
		# FIXME
		change_to_constate25() if ($config{'gameGuard'} eq "2");
	}
	$net->setState(1.3) if ($net->getState() == 1.2);
}

sub gameguard_request {
	my ($self, $args) = @_;

	return if (($net->version == 1 && $config{gameGuard} ne '2') || ($config{gameGuard} == 0));
	Poseidon::Client::getInstance()->query(
		substr($args->{RAW_MSG}, 0, $args->{RAW_MSG_SIZE})
	);
	debug "Querying Poseidon\n", "poseidon";
}

sub guild_allies_enemy_list {
	my ($self, $args) = @_;

	# Guild Allies/Enemy List
	# <len>.w (<type>.l <guildID>.l <guild name>.24B).*
	# type=0 Ally
	# type=1 Enemy

	# This is the length of the entire packet
	my $msg = $args->{RAW_MSG};
	my $len = unpack("v", substr($msg, 2, 2));

	# clear $guild{enemy} and $guild{ally} otherwise bot will misremember alliances -zdivpsa
	$guild{enemy} = {}; $guild{ally} = {};

	for (my $i = 4; $i < $len; $i += 32) {
		my ($type, $guildID, $guildName) = unpack('V2 Z24', substr($msg, $i, 32));
		$guildName = bytesToString($guildName);
		if ($type) {
			# Enemy guild
			$guild{enemy}{$guildID} = $guildName;
		} else {
			# Allied guild
			$guild{ally}{$guildID} = $guildName;
		}
		debug "Your guild is ".($type ? 'enemy' : 'ally')." with guild $guildID ($guildName)\n", "guild";
	}
}

sub guild_ally_request {
	my ($self, $args) = @_;

	my $ID = $args->{ID}; # is this a guild ID or account ID? Freya calls it an account ID
	my $name = bytesToString($args->{guildName}); # Type: String

	message TF("Incoming Request to Ally Guild '%s'\n", $name);
	$incomingGuild{ID} = $ID;
	$incomingGuild{Type} = 2;
	$timeout{ai_guildAutoDeny}{time} = time;
}

sub guild_broken {
	my ($self, $args) = @_;
	my $flag = $args->{flag};

	if ($flag == 2) {
		error T("Guild can not be undone: there are still members in the guild\n");
	} elsif ($flag == 1) {
		error T("Guild can not be undone: invalid key\n");
	} elsif ($flag == 0) {
		message T("Guild broken.\n");
		undef %{$char->{guild}};
		undef $char->{guildID};
		undef %guild;
	} else {
		error TF("Guild can not be undone: unknown reason (flag: %s)\n", $flag);
	}
}

sub guild_create_result {
	my ($self, $args) = @_;
	my $type = $args->{type};

	my %types = (
		0 => T("Guild create successful.\n"),
		2 => T("Guild create failed: Guild name already exists.\n"),
		3 => T("Guild create failed: Emperium is needed.\n")
	);
	if ($types{$type}) {
		message $types{$type};
	} else {
		message TF("Guild create: Unknown error %s\n", $type);
	}
}

sub guild_info {
	my ($self, $args) = @_;
	# Guild Info
	foreach (qw(ID lv conMember maxMember average exp exp_next tax tendency_left_right tendency_down_up name master castles_string)) {
		$guild{$_} = $args->{$_};
	}
	$guild{name} = bytesToString($args->{name});
	$guild{master} = bytesToString($args->{master});
	$guild{members}++; # count ourselves in the guild members count
}

sub guild_invite_result {
	my ($self, $args) = @_;

	my $type = $args->{type};

	my %types = (
		0 => T('Target is already in a guild.'),
		1 => T('Target has denied.'),
		2 => T('Target has accepted.'),
		3 => T('Your guild is full.')
	);
	if ($types{$type}) {
	    message TF("Guild join request: %s\n", $types{$type});
	} else {
	    message TF("Guild join request: Unknown %s\n", $type);
	}
}

sub guild_location {
	# FIXME: not implemented
	my ($self, $args) = @_;
	unless ($args->{x} > 0 && $args->{y} > 0) {
		# delete locator for ID
	} else {
		# add/replace locator for ID
	}
}

sub guild_leave {
	my ($self, $args) = @_;

	message TF("%s has left the guild.\n" .
		"Reason: %s\n", bytesToString($args->{name}), bytesToString($args->{message})), "schat";
}

sub guild_expulsion {
	my ($self, $args) = @_;

	message TF("%s has been removed from the guild.\n" .
		"Reason: %s\n", bytesToString($args->{name}), bytesToString($args->{message})), "schat";
}

sub search_store_open {
	my ($self, $args) = @_;
	message TF("Got type %s, you have %s searches\n", $args->{type}, $args->{searches});
}

sub search_store_result {
	my ($self, $args) = @_;
	message TF("Result len %s, first page: %s next: %s, searches: %s\n", $args->{len}, $args->{first_page}, $args->{has_next_page}, $args->{searches});
	
	for (my $offset = 0; ($offset + 106) < $args->{len}; $offset += 106) {
	my %item;
		($item{SSI_ID},
			$item{AID},
			$item{store_name},
			$item{item_id},
			$item{item_type},
			$item{price},
			$item{count},
			$item{refine},
			$item{card}[0],
			$item{card}[1],
			$item{card}[2],
			$item{card}[3]) = unpack('V2 Z80 v C V v C v4', substr($args->{searchInfo}, $offset, 106));
		message TF("%s %s %s %s\n", $item{store_name}, $item{item_id},$item{count}, $item{price});
	}
}

sub guild_member_online_status {
	my ($self, $args) = @_;

	foreach my $guildmember (@{$guild{member}}) {
		if ($guildmember->{charID} eq $args->{charID}) {
			if ($guildmember->{online} = $args->{online}) {
				message TF("Guild member %s logged in.\n", $guildmember->{name}), "guildchat";
			} else {
				message TF("Guild member %s logged out.\n", $guildmember->{name}), "guildchat";
			}
			last;
		}
	}
}

sub misc_effect {
	my ($self, $args) = @_;

	my $actor = Actor::get($args->{ID});
	message sprintf(
		$actor->verb(T("%s use effect: %s\n"), T("%s uses effect: %s\n")),
		$actor, defined $effectName{$args->{effect}} ? $effectName{$args->{effect}} : T("Unknown #")."$args->{effect}"
	), 'effect'
}

sub guild_members_title_list {
	my ($self, $args) = @_;

	my $newmsg;
	my $msg = $args->{RAW_MSG};
	my $msg_size = $args->{RAW_MSG_SIZE};

	$self->decrypt(\$newmsg, substr($msg, 4, length($msg) - 4));
	$msg = substr($msg, 0, 4) . $newmsg;
	my $gtIndex;
	for (my $i = 4; $i < $msg_size; $i+=28) {
		$gtIndex = unpack('V', substr($msg, $i, 4));
		$guild{positions}[$gtIndex]{title} = bytesToString(unpack('Z24', substr($msg, $i + 4, 24)));
	}
}

sub guild_name {
	my ($self, $args) = @_;

	my $guildID = $args->{guildID};
	my $emblemID = $args->{emblemID};
	my $mode = $args->{mode};
	my $guildName = bytesToString($args->{guildName});
	$char->{guild}{name} = $guildName;
	$char->{guildID} = $guildID;
	$char->{guild}{emblem} = $emblemID;

	$messageSender->sendGuildMasterMemberCheck();	# Is this necessary?? (requests for guild info packet 014E)
	$messageSender->sendGuildRequestInfo(0);	#requests for guild info packet 01B6 and 014C
	$messageSender->sendGuildRequestInfo(1);	#requests for guild member packet 0166 and 0154
	debug "guild name: $guildName\n";
}

sub guild_request {
	my ($self, $args) = @_;

	# Guild request
	my $ID = $args->{ID};
	my $name = bytesToString($args->{name});
	message TF("Incoming Request to join Guild '%s'\n", $name);
	$incomingGuild{'ID'} = $ID;
	$incomingGuild{'Type'} = 1;
	$timeout{'ai_guildAutoDeny'}{'time'} = time;
}

sub identify {
	my ($self, $args) = @_;
	if ($args->{flag} == 0) {
		my $item = $char->inventory->getByServerIndex($args->{index});
		$item->{identified} = 1;
		$item->{type_equip} = $itemSlots_lut{$item->{nameID}};
		message TF("Item Identified: %s (%d)\n", $item->{name}, $item->{invIndex}), "info";
	} else {
		message T("Item Appraisal has failed.\n");
	}
	undef @identifyID;
}

# TODO: store this state
sub ignore_all_result {
	my ($self, $args) = @_;
	if ($args->{type} == 0) {
		message T("All Players ignored\n");
	} elsif ($args->{type} == 1) {
		if ($args->{error} == 0) {
			message T("All players unignored\n");
		}
	}
}

# TODO: store list of ignored players
sub ignore_player_result {
	my ($self, $args) = @_;
	if ($args->{type} == 0) {
		message T("Player ignored\n");
	} elsif ($args->{type} == 1) {
		if ($args->{error} == 0) {
			message T("Player unignored\n");
		}
	}
}

sub party_location {
	my ($self, $args) = @_;

	my $ID = $args->{ID};

	if ($char->{party}{users}{$ID}) {
		$char->{party}{users}{$ID}{pos}{x} = $args->{x};
		$char->{party}{users}{$ID}{pos}{y} = $args->{y};
		$char->{party}{users}{$ID}{online} = 1;
		debug "Party member location: $char->{party}{users}{$ID}{name} - $args->{x}, $args->{y}\n", "parseMsg";
	}
}

sub pet_capture_result {
	my ($self, $args) = @_;

	if ($args->{success}) {
		message T("Pet capture success\n"), "info";
	} else {
		message T("Pet capture failed\n"), "info";
	}
}

sub pet_emotion {
	my ($self, $args) = @_;

	my ($ID, $type) = ($args->{ID}, $args->{type});

	my $emote = $emotions_lut{$type}{display} || "/e$type";
	if ($pets{$ID}) {
		message $pets{$ID}->name . " : $emote\n", "emotion";
	}
}

sub pet_food {
	my ($self, $args) = @_;
	if ($args->{success}) {
		message TF("Fed pet with %s\n", itemNameSimple($args->{foodID})), "pet";
	} else {
		error TF("Failed to feed pet with %s: no food in inventory.\n", itemNameSimple($args->{foodID}));
	}
}

sub pet_info {
	my ($self, $args) = @_;
	$pet{name} = bytesToString($args->{name});
	$pet{renameflag} = $args->{renameflag};
	$pet{level} = $args->{level};
	$pet{hungry} = $args->{hungry};
	$pet{friendly} = $args->{friendly};
	$pet{accessory} = $args->{accessory};
	$pet{type} = $args->{type} if (exists $args->{type});
	debug "Pet status: name=$pet{name} name_set=". ($pet{renameflag} ? 'yes' : 'no') ." level=$pet{level} hungry=$pet{hungry} intimacy=$pet{friendly} accessory=".itemNameSimple($pet{accessory})." type=".($pet{type}||"N/A")."\n", "pet";
}

sub pet_info2 {
	my ($self, $args) = @_;
	my ($type, $ID, $value) = @{$args}{qw(type ID value)};

	# receive information about your pet

	# related freya functions: clif_pet_equip clif_pet_performance clif_send_petdata

	# these should never happen, pets should spawn like normal actors (at least on Freya)
	# this isn't even very useful, do we want random pets with no location info?
	#if (!$pets{$ID} || !%{$pets{$ID}}) {
	#	binAdd(\@petsID, $ID);
	#	$pets{$ID} = {};
	#	%{$pets{$ID}} = %{$monsters{$ID}} if ($monsters{$ID} && %{$monsters{$ID}});
	#	$pets{$ID}{'name_given'} = "Unknown";
	#	$pets{$ID}{'binID'} = binFind(\@petsID, $ID);
	#	debug "Pet spawned (unusually): $pets{$ID}{'name'} ($pets{$ID}{'binID'})\n", "parseMsg";
	#}
	#if ($monsters{$ID}) {
	#	if (%{$monsters{$ID}}) {
	#		objectRemoved('monster', $ID, $monsters{$ID});
	#	}
	#	# always clear these in case
	#	binRemove(\@monstersID, $ID);
	#	delete $monsters{$ID};
	#}

	if ($type == 0) {
		# You own no pet.
		undef $pet{ID};

	} elsif ($type == 1) {
		$pet{friendly} = $value;
		debug "Pet friendly: $value\n";

	} elsif ($type == 2) {
		$pet{hungry} = $value;
		debug "Pet hungry: $value\n";

	} elsif ($type == 3) {
		# accessory info for any pet in range
		#debug "Pet accessory info: $value\n";

	} elsif ($type == 4) {
		# performance info for any pet in range
		#debug "Pet performance info: $value\n";

	} elsif ($type == 5) {
		# You own pet with this ID
		$pet{ID} = $ID;
	}
}

sub private_message {
	my ($self, $args) = @_;
	my ($newmsg, $msg); # Type: Bytes

	return unless changeToInGameState();

	# Type: String
	my $privMsgUser = bytesToString($args->{privMsgUser});
	my $privMsg = bytesToString($args->{privMsg});

	if ($privMsgUser ne "" && binFind(\@privMsgUsers, $privMsgUser) eq "") {
		push @privMsgUsers, $privMsgUser;
		Plugins::callHook('parseMsg/addPrivMsgUser', {
			user => $privMsgUser,
			msg => $privMsg,
			userList => \@privMsgUsers
		});
	}

	stripLanguageCode(\$privMsg);
	chatLog("pm", TF("(From: %s) : %s\n", $privMsgUser, $privMsg)) if ($config{'logPrivateChat'});
 	message TF("(From: %s) : %s\n", $privMsgUser, $privMsg), "pm";

	ChatQueue::add('pm', undef, $privMsgUser, $privMsg);
	Plugins::callHook('packet_privMsg', {
		privMsgUser => $privMsgUser,
		privMsg => $privMsg,
		MsgUser => $privMsgUser,
		Msg => $privMsg
	});

	if ($config{dcOnPM} && $AI == AI::AUTO) {
		chatLog("k", T("*** You were PM'd, auto disconnect! ***\n"));
		message T("Disconnecting on PM!\n");
		quit();
	}
}

sub private_message_sent {
	my ($self, $args) = @_;
	if ($args->{type} == 0) {
 		message TF("(To %s) : %s\n", $lastpm[0]{'user'}, $lastpm[0]{'msg'}), "pm/sent";
		chatLog("pm", "(To: $lastpm[0]{user}) : $lastpm[0]{msg}\n") if ($config{'logPrivateChat'});

		Plugins::callHook('packet_sentPM', {
			to => $lastpm[0]{user},
			msg => $lastpm[0]{msg}
		});

	} elsif ($args->{type} == 1) {
		warning TF("%s is not online\n", $lastpm[0]{user});
	} elsif ($args->{type} == 2) {
		warning TF("Player %s ignored your message\n", $lastpm[0]{user});
	} else {
		warning TF("Player %s doesn't want to receive messages\n", $lastpm[0]{user});
	}
	shift @lastpm;
}

sub received_character_ID_and_Map {
	my ($self, $args) = @_;
	message T("Received character ID and Map IP from Character Server\n"), "connection";
	$net->setState(4);
	undef $conState_tries;
	$charID = $args->{charID};

	if ($net->version == 1) {
		undef $masterServer;
		$masterServer = $masterServers{$config{master}} if ($config{master} ne "");
	}

	my ($map) = $args->{mapName} =~ /([\s\S]*)\./; # cut off .gat
	my $map_noinstance;
	($map_noinstance, undef) = Field::nameToBaseName(undef, $map); # Hack to clean up InstanceID
	if (!$field || $map ne $field->name()) {
		eval {
			$field = new Field(name => $map);
		};
		if (my $e = caught('FileNotFoundException', 'IOException')) {
			error TF("Cannot load field %s: %s\n", $map_noinstance, $e);
			undef $field;
		} elsif ($@) {
			die $@;
		}
	}

	$map_ip = makeIP($args->{mapIP});
	$map_ip = $masterServer->{ip} if ($masterServer && $masterServer->{private});
	$map_port = $args->{mapPort};
	message TF("----------Game Info----------\n" .
		"Char ID: %s (%s)\n" .
		"MAP Name: %s\n" .
		"MAP IP: %s\n" .
		"MAP Port: %s\n" .
		"-----------------------------\n", getHex($charID), unpack("V1", $charID),
		$args->{mapName}, $map_ip, $map_port), "connection";
	checkAllowedMap($map_noinstance);
	message(T("Closing connection to Character Server\n"), "connection") unless ($net->version == 1);
	$net->serverDisconnect(1);
	main::initStatVars();
}

sub received_sync {
	return unless changeToInGameState();
	debug "Received Sync\n", 'parseMsg', 2;
	$timeout{'play'}{'time'} = time;
}

sub refine_result {
	my ($self, $args) = @_;
	if ($args->{fail} == 0) {
		message TF("You successfully refined a weapon (ID %s)!\n", $args->{nameID});
	} elsif ($args->{fail} == 1) {
		message TF("You failed to refine a weapon (ID %s)!\n", $args->{nameID});
	} elsif ($args->{fail} == 2) {
		message TF("You successfully made a potion (ID %s)!\n", $args->{nameID});
	} elsif ($args->{fail} == 3) {
		message TF("You failed to make a potion (ID %s)!\n", $args->{nameID});
	} else {
		message TF("You tried to refine a weapon (ID %s); result: unknown %s\n", $args->{nameID}, $args->{fail});
	}
}

sub blacksmith_points {
	my ($self, $args) = @_;
	message TF("[POINT] Blacksmist Ranking Point is increasing by %s. Now, The total is %s points.\n", $args->{points}, $args->{total}, "list");
}


sub alchemist_point {
	my ($self, $args) = @_;
	message TF("[POINT] Alchemist Ranking Point is increasing by %s. Now, The total is %s points.\n", $args->{points}, $args->{total}, "list");
}

sub repair_result {
	my ($self, $args) = @_;
	undef $repairList;
	my $itemName = itemNameSimple($args->{nameID});
	if ($args->{flag}) {
		message TF("Repair of %s failed.\n", $itemName);
	} else {
		message TF("Successfully repaired %s.\n", $itemName);
	}
}

sub resurrection {
	my ($self, $args) = @_;

	my $targetID = $args->{targetID};
	my $player = $playersList->getByID($targetID);
	my $type = $args->{type};

	if ($targetID eq $accountID) {
		message T("You have been resurrected\n"), "info";
		undef $char->{'dead'};
		undef $char->{'dead_time'};
		$char->{'resurrected'} = 1;

	} else {
		if ($player) {
			undef $player->{'dead'};
			$player->{deltaHp} = 0;
		}
		message TF("%s has been resurrected\n", getActorName($targetID)), "info";
	}
}

sub secure_login_key {
	my ($self, $args) = @_;
	$secureLoginKey = $args->{secure_key};
	debug sprintf("Secure login key: %s\n", getHex($args->{secure_key})), 'connection';
}

sub self_chat {
	my ($self, $args) = @_;
	my ($message, $chatMsgUser, $chatMsg); # Type: String

	$message = bytesToString($args->{message});

	($chatMsgUser, $chatMsg) = $message =~ /([\s\S]*?) : ([\s\S]*)/;
	# Note: $chatMsgUser/Msg may be undefined. This is the case on
	# eAthena servers: it uses this packet for non-chat server messages.

	if (defined $chatMsgUser) {
		stripLanguageCode(\$chatMsg);
		$message = $chatMsgUser . " : " . $chatMsg;
	}

	chatLog("c", "$message\n") if ($config{'logChat'});
	message "$message\n", "selfchat";

	Plugins::callHook('packet_selfChat', {
		user => $chatMsgUser,
		msg => $chatMsg
	});
}

sub sync_request {
	my ($self, $args) = @_;

	# 0187 - long ID
	# I'm not sure what this is. In inRO this seems to have something
	# to do with logging into the game server, while on
	# oRO it has got something to do with the sync packet.
	if ($masterServer->{serverType} == 1) {
		my $ID = $args->{ID};
		if ($ID == $accountID) {
			$timeout{ai_sync}{time} = time;
			$messageSender->sendSync() unless ($net->clientAlive);
			debug "Sync packet requested\n", "connection";
		} else {
			warning T("Sync packet requested for wrong ID\n");
		}
	}
}

# 00B3
# TODO: add real client messages and logic?
# ClientLogic: LoginStartMode = 5; ShowLoginScreen;
sub switch_character {
	my ($self, $args) = @_;
	# User is switching characters in X-Kore
	$net->setState(Network::CONNECTED_TO_MASTER_SERVER);
	$net->serverDisconnect();

	# FIXME better support for multiple received_characters packets
	undef @chars;

	debug "result: $args->{result}\n";
}

sub taekwon_rank {
	my ($self, $args) = @_;
	message T("TaeKwon Mission Rank : ".$args->{rank}."\n"), "info";
}

sub no_teleport {
	my ($self, $args) = @_;
	my $fail = $args->{fail};

	my $errorMessage;
	if ($fail == 0) {
		$errorMessage = T("Unavailable Area To Teleport");
	#	AI::clear(qw/teleport/);
	} elsif ($fail == 1) {
		$errorMessage = T("Unavailable Area To Memo");
	} else {
		$errorMessage = TF("Unavailable Area To Teleport (fail code %s)", $fail);
	}
	
	error sprintf("%s\n", $errorMessage);
	
	Plugins::callHook('packet_no_teleport', {
		failType    => $fail,
		failMessage => $errorMessage
	});
	
}


sub pvp_rank {
	my ($self, $args) = @_;

	# 9A 01 - 14 bytes long
	my $ID = $args->{ID};
	my $rank = $args->{rank};
	my $num = $args->{num};;
	if ($rank != $ai_v{temp}{pvp_rank} ||
	    $num != $ai_v{temp}{pvp_num}) {
		$ai_v{temp}{pvp_rank} = $rank;
		$ai_v{temp}{pvp_num} = $num;
		if ($ai_v{temp}{pvp}) {
			message TF("Your PvP rank is: %s/%s\n", $rank, $num), "map_event";
		}
	}
}

sub sense_result {
	my ($self, $args) = @_;
	# nameID level size hp def race mdef element ice earth fire wind poison holy dark spirit undead
	my @race_lut = qw(Formless Undead Beast Plant Insect Fish Demon Demi-Human Angel Dragon Boss Non-Boss);
	my @size_lut = qw(Small Medium Large);
	message TF("=====================Sense========================\n" .
			"Monster: %-16s Level: %-12s\n" .
			"Size:    %-16s Race:  %-12s\n" .
			"Def:     %-16s MDef:  %-12s\n" .
			"Element: %-16s HP:    %-12s\n" .
			"=================Damage Modifiers=================\n" .
			"Ice: %-3s     Earth: %-3s  Fire: %-3s  Wind: %-3s\n" .
			"Poison: %-3s  Holy: %-3s   Dark: %-3s  Spirit: %-3s\n" .
			"Undead: %-3s\n" .
			"==================================================\n",
			$monsters_lut{$args->{nameID}}, $args->{level}, $size_lut[$args->{size}], $race_lut[$args->{race}],
			$args->{def}, $args->{mdef}, $elements_lut{$args->{element}}, $args->{hp},
			$args->{ice}, $args->{earth}, $args->{fire}, $args->{wind}, $args->{poison}, $args->{holy}, $args->{dark},
			$args->{spirit}, $args->{undead}), "list";
}

# Your shop has sold an item
# Need a hook.
sub shop_sold {
	my ($self, $args) = @_;

	# sold something
	my $number = $args->{number};
	my $amount = $args->{amount};

	$articles[$number]{sold} += $amount;
	my $earned = $amount * $articles[$number]{price};
	$shopEarned += $earned;
	$articles[$number]{quantity} -= $amount;
	my $msg = TF("sold: %s - %s %sz\n", $amount, $articles[$number]{name}, $earned);
	shopLog($msg);
	message($msg, "sold");
	if ($articles[$number]{quantity} < 1) {
		message TF("sold out: %s\n", $articles[$number]{name}), "sold";
		#$articles[$number] = "";
		if (!--$articles){
			message T("Items have been sold out.\n"), "sold";
			closeShop();
		}
	}
}

# TODO:
# Add 'dispose' support
sub skill_cast {
	my ($self, $args) = @_;

	return unless changeToInGameState();
	my $sourceID = $args->{sourceID};
	my $targetID = $args->{targetID};
	my $x = $args->{x};
	my $y = $args->{y};
	my $skillID = $args->{skillID};
	my $type = $args->{type};
	my $wait = $args->{wait};
	my ($dist, %coords);

	# Resolve source and target
	my $source = Actor::get($sourceID);
	my $target = Actor::get($targetID);
	my $verb = $source->verb('are casting', 'is casting');

	Misc::checkValidity("skill_cast part 1");

	my $skill = new Skill(idn => $skillID);
	$source->{casting} = {
		skill => $skill,
		target => $target,
		x => $x,
		y => $y,
		startTime => time,
		castTime => $wait
	};
	# Since we may have a circular reference, weaken this reference
	# to prevent memory leaks.
	Scalar::Util::weaken($source->{casting}{target});

	my $targetString;
	if ($x != 0 || $y != 0) {
		# If $dist is positive we are in range of the attack?
		$coords{x} = $x;
		$coords{y} = $y;
		$dist = judgeSkillArea($skillID) - distance($char->{pos_to}, \%coords);
			$targetString = "location ($x, $y)";
		undef $targetID;
	} else {
		$targetString = $target->nameString($source);
	}

	# Perform trigger actions
	if ($sourceID eq $accountID) {
		$char->{time_cast} = time;
		$char->{time_cast_wait} = $wait / 1000;
		delete $char->{cast_cancelled};
	}
	countCastOn($sourceID, $targetID, $skillID, $x, $y);

	Misc::checkValidity("skill_cast part 2");

	my $domain = ($sourceID eq $accountID) ? "selfSkill" : "skill";
	my $disp = skillCast_string($source, $target, $x, $y, $skill->getName(), $wait);
	message $disp, $domain, 1;

	Plugins::callHook('is_casting', {
		sourceID => $sourceID,
		targetID => $targetID,
		source => $source,
		target => $target,
		skillID => $skillID,
		skill => $skill,
		time => $source->{casting}{time},
		castTime => $wait,
		x => $x,
		y => $y
	});

	Misc::checkValidity("skill_cast part 3");

	# Skill Cancel
	my $monster = $monstersList->getByID($sourceID);
	my $control;
	$control = mon_control($monster->name,$monster->{nameID}) if ($monster);
	if ($AI == AI::AUTO && $control->{skillcancel_auto}) {
		if ($targetID eq $accountID || $dist > 0 || (AI::action eq "attack" && AI::args->{ID} ne $sourceID)) {
			message TF("Monster Skill - switch Target to : %s (%d)\n", $monster->name, $monster->{binID});
			$char->sendAttackStop;
			AI::dequeue;
			attack($sourceID);
		}

		# Skill area casting -> running to monster's back
		my $ID;
		if ($dist > 0 && AI::action eq "attack" && ($ID = AI::args->{ID}) && (my $monster2 = $monstersList->getByID($ID))) {
			# Calculate X axis
			if ($char->{pos_to}{x} - $monster2->{pos_to}{x} < 0) {
				$coords{x} = $monster2->{pos_to}{x} + 3;
			} else {
				$coords{x} = $monster2->{pos_to}{x} - 3;
			}
			# Calculate Y axis
			if ($char->{pos_to}{y} - $monster2->{pos_to}{y} < 0) {
				$coords{y} = $monster2->{pos_to}{y} + 3;
			} else {
				$coords{y} = $monster2->{pos_to}{y} - 3;
			}

			my (%vec, %pos);
			getVector(\%vec, \%coords, $char->{pos_to});
			moveAlongVector(\%pos, $char->{pos_to}, \%vec, distance($char->{pos_to}, \%coords));
			ai_route($field->baseName, $pos{x}, $pos{y},
				maxRouteDistance => $config{attackMaxRouteDistance},
				maxRouteTime => $config{attackMaxRouteTime},
				noMapRoute => 1);
			message TF("Avoid casting Skill - switch position to : %s,%s\n", $pos{x}, $pos{y}), 1;
		}

		Misc::checkValidity("skill_cast part 4");
	}
}

# TODO: use $args->{type} if present
sub skill_update {
	my ($self, $args) = @_;

	my ($ID, $lv, $sp, $range, $up) = ($args->{skillID}, $args->{lv}, $args->{sp}, $args->{range}, $args->{up});

	my $skill = new Skill(idn => $ID);
	my $handle = $skill->getHandle();
	my $name = $skill->getName();
	$char->{skills}{$handle}{lv} = $lv;
	$char->{skills}{$handle}{sp} = $sp;
	$char->{skills}{$handle}{range} = $range;
	$char->{skills}{$handle}{up} = $up;

	Skill::DynamicInfo::add($ID, $handle, $lv, $sp, $range, $skill->getTargetType(), Skill::OWNER_CHAR);

	Plugins::callHook('packet_charSkills', {
		ID => $ID,
		handle => $handle,
		level => $lv,
		upgradable => $up,
	});

	debug "Skill $name: $lv\n", "parseMsg";
}

sub skill_use {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	if (my $spell = $spells{$args->{sourceID}}) {
		# Resolve source of area attack skill
		$args->{sourceID} = $spell->{sourceID};
	}

	my $source = Actor::get($args->{sourceID});
	my $target = Actor::get($args->{targetID});
	$args->{source} = $source;
	$args->{target} = $target;
	delete $source->{casting};

	# Perform trigger actions
	if ($args->{switch} eq "0114") {
		$args->{damage} = intToSignedShort($args->{damage});
	} else {
		$args->{damage} = intToSignedInt($args->{damage});
	}
	updateDamageTables($args->{sourceID}, $args->{targetID}, $args->{damage}) if ($args->{damage} != -30000);
	setSkillUseTimer($args->{skillID}, $args->{targetID}) if (
		$args->{sourceID} eq $accountID
		or $char->{slaves} && $char->{slaves}{$args->{sourceID}}
	);
	setPartySkillTimer($args->{skillID}, $args->{targetID}) if (
		$args->{sourceID} eq $accountID
		or $char->{slaves} && $char->{slaves}{$args->{sourceID}}
		or $args->{sourceID} eq $args->{targetID} # wtf?
	);
	countCastOn($args->{sourceID}, $args->{targetID}, $args->{skillID});

	# Resolve source and target names
	my $skill = new Skill(idn => $args->{skillID});
	$args->{skill} = $skill;
	my $disp = skillUse_string($source, $target, $skill->getName(), $args->{damage},
		$args->{level}, ($args->{src_speed}));

	if ($args->{damage} != -30000 &&
	    $args->{sourceID} eq $accountID &&
		$args->{targetID} ne $accountID) {
		calcStat($args->{damage});
	}

	my $domain = ($args->{sourceID} eq $accountID) ? "selfSkill" : "skill";

	if ($args->{damage} == 0) {
		$domain = "attackMonMiss" if (($args->{sourceID} eq $accountID && $args->{targetID} ne $accountID) || ($char->{homunculus} && $args->{sourceID} eq $char->{homunculus}{ID} && $args->{targetID} ne $char->{homunculus}{ID}));
		$domain = "attackedMiss" if (($args->{sourceID} ne $accountID && $args->{targetID} eq $accountID) || ($char->{homunculus} && $args->{sourceID} ne $char->{homunculus}{ID} && $args->{targetID} eq $char->{homunculus}{ID}));

	} elsif ($args->{damage} != -30000) {
		$domain = "attackMon" if (($args->{sourceID} eq $accountID && $args->{targetID} ne $accountID) || ($char->{homunculus} && $args->{sourceID} eq $char->{homunculus}{ID} && $args->{targetID} ne $char->{homunculus}{ID}));
		$domain = "attacked" if (($args->{sourceID} ne $accountID && $args->{targetID} eq $accountID) || ($char->{homunculus} && $args->{sourceID} ne $char->{homunculus}{ID} && $args->{targetID} eq $char->{homunculus}{ID}));
	}

	if ((($args->{sourceID} eq $accountID) && ($args->{targetID} ne $accountID)) ||
	    (($args->{sourceID} ne $accountID) && ($args->{targetID} eq $accountID))) {
		my $status = sprintf("[%3d/%3d] ", $char->hp_percent, $char->sp_percent);
		$disp = $status.$disp;
	} elsif ($char->{slaves} && $char->{slaves}{$args->{sourceID}} && !$char->{slaves}{$args->{targetID}}) {
		my $status = sprintf("[%3d/%3d] ", $char->{slaves}{$args->{sourceID}}{hpPercent}, $char->{slaves}{$args->{sourceID}}{spPercent});
		$disp = $status.$disp;
	} elsif ($char->{slaves} && !$char->{slaves}{$args->{sourceID}} && $char->{slaves}{$args->{targetID}}) {
		my $status = sprintf("[%3d/%3d] ", $char->{slaves}{$args->{targetID}}{hpPercent}, $char->{slaves}{$args->{targetID}}{spPercent});
		$disp = $status.$disp;
	}
	$target->{sitting} = 0 unless $args->{type} == 4 || $args->{type} == 9 || $args->{damage} == 0;

	Plugins::callHook('packet_skilluse', {
			'skillID' => $args->{skillID},
			'sourceID' => $args->{sourceID},
			'targetID' => $args->{targetID},
			'damage' => $args->{damage},
			'amount' => 0,
			'x' => 0,
			'y' => 0,
			'disp' => \$disp
		});
	message $disp, $domain, 1;

	if ($args->{targetID} eq $accountID && $args->{damage} > 0) {
		$damageTaken{$source->{name}}{$skill->getName()} += $args->{damage};
	}
}

sub skill_use_failed {
	my ($self, $args) = @_;

	# skill fail/delay
	my $skillID = $args->{skillID};
	my $btype = $args->{btype};
	my $fail = $args->{fail};
	my $type = $args->{type};

	my %failtype = (
		0 => T('Basic'),
		1 => T('Insufficient SP'),
		2 => T('Insufficient HP'),
		3 => T('No Memo'),
		4 => T('Mid-Delay'),
		5 => T('No Zeny'),
		6 => T('Wrong Weapon Type'),
		7 => T('Red Gem Needed'),
		8 => T('Blue Gem Needed'),
		9 => TF('%s Overweight', '90%'),
		10 => T('Requirement'),
		13 => T('Need this within the water'),
		19 => T('Full Amulet'),
		29 => TF('Must have at least %s of base XP', '1%'),
		83 => T('Location not allowed to create chatroom/market')
		);

	my $errorMessage;
	if (exists $failtype{$type}) {
		$errorMessage = $failtype{$type};
	} else {
		$errorMessage = 'Unknown error';
	}

	warning TF("Skill %s failed: %s (error number %s)\n", Skill->new(idn => $skillID)->getName(), $errorMessage, $type), "skill";
	Plugins::callHook('packet_skillfail', {
		skillID     => $skillID,
		failType    => $type,
		failMessage => $errorMessage
	});
}


# Skill used on a set of map tile coordinates.
# Examples: Warp Portal/Teleport, Bard/Dancer skills, etc.
#
sub skill_use_location {
	my ($self, $args) = @_;

	# Skill used on coordinates
	my $skillID = $args->{skillID};
	my $sourceID = $args->{sourceID};
	my $lv = $args->{lv};
	my $x = $args->{x};
	my $y = $args->{y};

	# Perform trigger actions
	setSkillUseTimer($skillID) if $sourceID eq $accountID;

	# Resolve source name
	my $source = Actor::get($sourceID);
	my $skillName = Skill->new(idn => $skillID)->getName();
	my $disp = skillUseLocation_string($source, $skillName, $args);

	# Print skill use message
	my $domain = ($sourceID eq $accountID) ? "selfSkill" : "skill";
	message $disp, $domain;

	Plugins::callHook('packet_skilluse', {
		'skillID' => $skillID,
		'sourceID' => $sourceID,
		'targetID' => '',
		'damage' => 0,
		'amount' => $lv,
		'x' => $x,
		'y' => $y
	});
}
# TODO: a skill can fail, do something with $args->{success} == 0 (this means that the skill failed)
sub skill_used_no_damage {
	my ($self, $args) = @_;
	return unless changeToInGameState();

	# Skill used on target, with no damage done
	if (my $spell = $spells{$args->{sourceID}}) {
		# Resolve source of area attack skill
		$args->{sourceID} = $spell->{sourceID};
	}

	# Perform trigger actions
	# FIXME: setSkillUseTimer does many different things, so which of them "screw up monk comboing"?
	setSkillUseTimer($args->{skillID}, $args->{targetID}) if ($args->{sourceID} eq $accountID
		&& $skillsArea{$args->{skillHandle}} != 2); # ignore these skills because they screw up monk comboing
	setPartySkillTimer($args->{skillID}, $args->{targetID}) if
			$args->{sourceID} eq $accountID or $args->{sourceID} eq $args->{targetID};
	countCastOn($args->{sourceID}, $args->{targetID}, $args->{skillID});
	if ($args->{sourceID} eq $accountID) {
		my $pos = calcPosition($char);
		$char->{pos_to} = $pos;
		$char->{time_move} = 0;
		$char->{time_move_calc} = 0;
	}

	# Resolve source and target names
	my ($source, $target);
	$target = $args->{target} = Actor::get($args->{targetID});
	$source = $args->{source} = (
		$args->{sourceID} ne "\000\000\000\000"
		? Actor::get($args->{sourceID})
		: $target # for Heal generated by Potion Pitcher sourceID = 0
	);
	my $verb = $source->verb('use', 'uses');

	delete $source->{casting};

	# Print skill use message
	my $extra = "";
	if ($args->{skillID} == 28) {
		$extra = ": $args->{amount} hp gained";
		updateDamageTables($args->{sourceID}, $args->{targetID}, -$args->{amount});
	} elsif ($args->{amount} != 65535) {
		$extra = ": Lv $args->{amount}";
	}

	my $domain = ($args->{sourceID} eq $accountID) ? "selfSkill" : "skill";
	my $skill = $args->{skill} = new Skill(idn => $args->{skillID});
	my $disp = skillUseNoDamage_string($source, $target, $skill->getIDN(), $skill->getName(), $args->{amount});
	message $disp, $domain;

	# Set teleport time
	# TODO: remove, deprecated by Task::Teleport
	# if ($args->{sourceID} eq $accountID && $skill->getHandle() eq 'AL_TELEPORT') {
		# $timeout{ai_teleport_delay}{time} = time;
	# }

	if ($AI == AI::AUTO && $config{'autoResponseOnHeal'}) {
		# Handle auto-response on heal
		my $player = $playersList->getByID($args->{sourceID});
		if ($player && ($args->{skillID} == 28 || $args->{skillID} == 29 || $args->{skillID} == 34)) {
			if ($args->{targetID} eq $accountID) {
				chatLog("k", "***$source ".$skill->getName()." on $target$extra***\n");
				sendMessage("pm", getResponse("skillgoodM"), $player->name);
			} elsif ($monstersList->getByID($args->{targetID})) {
				chatLog("k", "***$source ".$skill->getName()." on $target$extra***\n");
				sendMessage("pm", getResponse("skillbadM"), $player->name);
			}
		}
	}
	Plugins::callHook('packet_skilluse', {
		skillID => $args->{skillID},
		sourceID => $args->{sourceID},
		targetID => $args->{targetID},
		damage => 0,
		amount => $args->{amount},
		x => 0,
		y => 0
	});
}


sub stats_info {
	my ($self, $args) = @_;
	return unless changeToInGameState();
	$char->{points_free} = $args->{points_free};
	$char->{str} = $args->{str};
	$char->{points_str} = $args->{points_str};
	$char->{agi} = $args->{agi};
	$char->{points_agi} = $args->{points_agi};
	$char->{vit} = $args->{vit};
	$char->{points_vit} = $args->{points_vit};
	$char->{int} = $args->{int};
	$char->{points_int} = $args->{points_int};
	$char->{dex} = $args->{dex};
	$char->{points_dex} = $args->{points_dex};
	$char->{luk} = $args->{luk};
	$char->{points_luk} = $args->{points_luk};
	$char->{attack} = $args->{attack};
	$char->{attack_bonus} = $args->{attack_bonus};
	$char->{attack_magic_min} = $args->{attack_magic_min};
	$char->{attack_magic_max} = $args->{attack_magic_max};
	$char->{def} = $args->{def};
	$char->{def_bonus} = $args->{def_bonus};
	$char->{def_magic} = $args->{def_magic};
	$char->{def_magic_bonus} = $args->{def_magic_bonus};
	$char->{hit} = $args->{hit};
	$char->{flee} = $args->{flee};
	$char->{flee_bonus} = $args->{flee_bonus};
	$char->{critical} = $args->{critical};
	debug	"Strength: $char->{str} #$char->{points_str}\n"
		."Agility: $char->{agi} #$char->{points_agi}\n"
		."Vitality: $char->{vit} #$char->{points_vit}\n"
		."Intelligence: $char->{int} #$char->{points_int}\n"
		."Dexterity: $char->{dex} #$char->{points_dex}\n"
		."Luck: $char->{luk} #$char->{points_luk}\n"
		."Attack: $char->{attack}\n"
		."Attack Bonus: $char->{attack_bonus}\n"
		."Magic Attack Min: $char->{attack_magic_min}\n"
		."Magic Attack Max: $char->{attack_magic_max}\n"
		."Defense: $char->{def}\n"
		."Defense Bonus: $char->{def_bonus}\n"
		."Magic Defense: $char->{def_magic}\n"
		."Magic Defense Bonus: $char->{def_magic_bonus}\n"
		."Hit: $char->{hit}\n"
		."Flee: $char->{flee}\n"
		."Flee Bonus: $char->{flee_bonus}\n"
		."Critical: $char->{critical}\n"
		."Status Points: $char->{points_free}\n", "parseMsg";
}

sub storage_closed {
	message T("Storage closed.\n"), "storage";
	delete $ai_v{temp}{storage_opened};
	delete $storage{opened};
	Plugins::callHook('packet_storage_close');

	# Storage log
	writeStorageLog(0);

	if ($char->{dcOnEmptyItems} ne "") {
		message TF("Disconnecting on empty %s!\n", $char->{dcOnEmptyItems});
		chatLog("k", TF("Disconnecting on empty %s!\n", $char->{dcOnEmptyItems}));
		quit();
	}
}

sub storage_item_added {
	my ($self, $args) = @_;

	my $index = $args->{index};
	my $amount = $args->{amount};

	my $item = $storage{$index} ||= Actor::Item->new;
	if ($item->{amount}) {
		$item->{amount} += $amount;
	} else {
		binAdd(\@storageID, $index);
		$item->{nameID} = $args->{nameID};
		$item->{index} = $index;
		$item->{amount} = $amount;
		$item->{type} = $args->{type};
		$item->{identified} = $args->{identified};
		$item->{broken} = $args->{broken};
		$item->{upgrade} = $args->{upgrade};
		$item->{cards} = $args->{cards};
		$item->{name} = itemName($item);
		$item->{binID} = binFind(\@storageID, $index);
	}
	message TF("Storage Item Added: %s (%d) x %s\n", $item->{name}, $item->{binID}, $amount), "storage", 1;
	$itemChange{$item->{name}} += $amount;
	$args->{item} = $item;
}

sub storage_item_removed {
	my ($self, $args) = @_;

	my ($index, $amount) = @{$args}{qw(index amount)};

	my $item = $storage{$index};
	$item->{amount} -= $amount;
	message TF("Storage Item Removed: %s (%d) x %s\n", $item->{name}, $item->{binID}, $amount), "storage";
	$itemChange{$item->{name}} -= $amount;
	$args->{item} = $item;
	if ($item->{amount} <= 0) {
		delete $storage{$index};
		binRemove(\@storageID, $index);
	}
}

sub storage_items_nonstackable {
	my ($self, $args) = @_;

	$self->_items_list({
		class => 'Actor::Item',
		hook => 'packet_storage',
		debug_str => 'Non-Stackable Storage Item',
		items => [$self->parse_items_nonstackable($args)],
		adder => sub { $_[0]{binID} = binAdd(\@storageID, $_[0]{index}); $storage{$_[0]{index}} = $_[0] },
	});

	$storageTitle = exists $args->{title} ? $args->{title} : undef;
}

sub storage_items_stackable {
	my ($self, $args) = @_;

	undef %storage;
	undef @storageID;

	$self->_items_list({
		class => 'Actor::Item',
		hook => 'packet_storage',
		debug_str => 'Stackable Storage Item',
		items => [$self->parse_items_stackable($args)],
		adder => sub { $_[0]{binID} = binAdd(\@storageID, $_[0]{index}); $storage{$_[0]{index}} = $_[0] },
		callback => sub {
			my ($local_item) = @_;

			$local_item->{amount} = $local_item->{amount} & ~0x80000000;
		},
	});

	$storageTitle = exists $args->{title} ? $args->{title} : undef;
}

sub storage_opened {
	my ($self, $args) = @_;
	$storage{items} = $args->{items};
	$storage{items_max} = $args->{items_max};

	$ai_v{temp}{storage_opened} = 1;
	if (!$storage{opened}) {
		$storage{opened} = 1;
		$storage{openedThisSession} = 1;
		message defined $storageTitle ? TF("Storage '%s' opened.\n", $storageTitle) : T("Storage opened.\n"), "storage";
		Plugins::callHook('packet_storage_open');
	}
}

sub storage_password_request {
	my ($self, $args) = @_;

	if ($args->{flag} == 0) {
		if ($args->{switch} eq '023E') {
			message T("Please enter a new character password:\n");
		} else {
			if ($config{storageAuto_password} eq '') {
				my $input = $interface->query(T("You've never set a storage password before.\nYou must set a storage password before you can use the storage.\nPlease enter a new storage password:"), isPassword => 1);
				if (!defined($input)) {
					return;
				}
				configModify('storageAuto_password', $input, 1);
			}
		}

		my @key = split /[, ]+/, $config{storageEncryptKey};
		if (!@key) {
			error (($args->{switch} eq '023E') ?
				T("Unable to send character password. You must set the 'storageEncryptKey' option in config.txt or servers.txt.\n") :
				T("Unable to send storage password. You must set the 'storageEncryptKey' option in config.txt or servers.txt.\n"));
			return;
		}
		my $crypton = new Utils::Crypton(pack("V*", @key), 32);
		my $num = ($args->{switch} eq '023E') ? $config{charSelect_password} : $config{storageAuto_password};
		$num = sprintf("%d%08d", length($num), $num);
		my $ciphertextBlock = $crypton->encrypt(pack("V*", $num, 0, 0, 0));
		message TF("Storage password set to: %s\n", $config{storageAuto_password}), "success";
		$messageSender->sendStoragePassword($ciphertextBlock, 2);
		$messageSender->sendStoragePassword($ciphertextBlock, 3);

	} elsif ($args->{flag} == 1) {
		if ($args->{switch} eq '023E') {
			if ($config{charSelect_password} eq '') {
				my $input = $interface->query(T("Please enter your character password."), isPassword => 1);
				if (!defined($input)) {
					return;
				}
				configModify('charSelect_password', $input, 1);
				message TF("Character password set to: %s\n", $input), "success";
			}
		} else {
			if ($config{storageAuto_password} eq '') {
				my $input = $interface->query(T("Please enter your storage password."), isPassword => 1);
				if (!defined($input)) {
					return;
				}
				configModify('storageAuto_password', $input, 1);
				message TF("Storage password set to: %s\n", $input), "success";
			}
		}

		my @key = split /[, ]+/, $config{storageEncryptKey};
		if (!@key) {
			error (($args->{switch} eq '023E') ?
				T("Unable to send character password. You must set the 'storageEncryptKey' option in config.txt or servers.txt.\n") :
				T("Unable to send storage password. You must set the 'storageEncryptKey' option in config.txt or servers.txt.\n"));
			return;
		}
		my $crypton = new Utils::Crypton(pack("V*", @key), 32);
		my $num = ($args->{switch} eq '023E') ? $config{charSelect_password} : $config{storageAuto_password};
		$num = sprintf("%d%08d", length($num), $num);
		my $ciphertextBlock = $crypton->encrypt(pack("V*", $num, 0, 0, 0));
		$messageSender->sendStoragePassword($ciphertextBlock, 3);

	} elsif ($args->{flag} == 8) {	# apparently this flag means that you have entered the wrong password
									# too many times, and now the server is blocking you from using storage
		error T("You have entered the wrong password 5 times. Please try again later.\n");
		# temporarily disable storageAuto
		$config{storageAuto} = 0;
		my $index = AI::findAction('storageAuto');
		if (defined $index) {
			AI::args($index)->{done} = 1;
			while (AI::action ne 'storageAuto') {
				AI::dequeue;
			}
		}
	} else {
		debug(($args->{switch} eq '023E') ?
			"Character password: unknown flag $args->{flag}\n" :
			"Storage password: unknown flag $args->{flag}\n");
	}
}

# TODO
sub storage_password_result {
	my ($self, $args) = @_;

	# TODO:
    # STORE_PASSWORD_EMPTY =  0x0
    # STORE_PASSWORD_EXIST =  0x1
    # STORE_PASSWORD_CHANGE =  0x2
    # STORE_PASSWORD_CHECK =  0x3
    # STORE_PASSWORD_PANALTY =  0x8

	if ($args->{type} == 4) { # STORE_PASSWORD_CHANGE_OK =  0x4
		message T("Successfully changed storage password.\n"), "success";
	} elsif ($args->{type} == 5) { # STORE_PASSWORD_CHANGE_NG =  0x5
		error T("Error: Incorrect storage password.\n");
	} elsif ($args->{type} == 6) { # STORE_PASSWORD_CHECK_OK =  0x6
		message T("Successfully entered storage password.\n"), "success";
	} elsif ($args->{type} == 7) { # STORE_PASSWORD_CHECK_NG =  0x7
		error T("Error: Incorrect storage password.\n");
		# disable storageAuto or the Kafra storage will be blocked
		configModify("storageAuto", 0);
		my $index = AI::findAction('storageAuto');
		if (defined $index) {
			AI::args($index)->{done} = 1;
			while (AI::action ne 'storageAuto') {
				AI::dequeue;
			}
		}
	} else {
		#message "Storage password: unknown type $args->{type}\n";
	}

	# $args->{val}
	# unknown, what is this for?
}

sub initialize_message_id_encryption {
	my ($self, $args) = @_;
	if ($masterServer->{messageIDEncryption} ne '0') {
		$messageSender->sendMessageIDEncryptionInitialized();

		my @c;
		my $shtmp = $args->{param1};
		for (my $i = 8; $i > 0; $i--) {
			$c[$i] = $shtmp & 0x0F;
			$shtmp >>= 4;
		}
		my $w = ($c[6]<<12) + ($c[4]<<8) + ($c[7]<<4) + $c[1];
		$enc_val1 = ($c[2]<<12) + ($c[3]<<8) + ($c[5]<<4) + $c[8];
		$enc_val2 = (((($enc_val1 ^ 0x0000F3AC) + $w) << 16) | (($enc_val1 ^ 0x000049DF) + $w)) ^ $args->{param2};
	}
}

sub top10_alchemist_rank {
	my ($self, $args) = @_;

	my $textList = bytesToString(top10Listing($args));
	message TF("============= ALCHEMIST RANK ================\n" .
		"#    Name                             Points\n".
		"%s" .
		"=============================================\n", $textList), "list";
}

sub top10_blacksmith_rank {
	my ($self, $args) = @_;

	my $textList = bytesToString(top10Listing($args));
	message TF("============= BLACKSMITH RANK ===============\n" .
		"#    Name                             Points\n".
		"%s" .
		"=============================================\n", $textList), "list";
}

sub top10_pk_rank {
	my ($self, $args) = @_;

	my $textList = bytesToString(top10Listing($args));
	message TF("================ PVP RANK ===================\n" .
		"#    Name                             Points\n".
		"%s" .
		"=============================================\n", $textList), "list";
}

sub top10_taekwon_rank {
	my ($self, $args) = @_;

	my $textList = bytesToString(top10Listing($args));
	message TF("=============== TAEKWON RANK ================\n" .
		"#    Name                             Points\n".
		"%s" .
		"=============================================\n", $textList), "list";
}

sub vender_found {
	my ($self, $args) = @_;
	my $ID = $args->{ID};

	if (!$venderLists{$ID} || !%{$venderLists{$ID}}) {
		binAdd(\@venderListsID, $ID);
		Plugins::callHook('packet_vender', {ID => $ID});
	}
	$venderLists{$ID}{title} = bytesToString($args->{title});
	$venderLists{$ID}{id} = $ID;
}


sub vender_items_list {
	my ($self, $args) = @_;

	my $msg = $args->{RAW_MSG};
	my $msg_size = $args->{RAW_MSG_SIZE};
	my $headerlen;

	# a hack, but the best we can do now
	if ($args->{switch} eq "0133") {
		$headerlen = 8;
	} else { # switch 0800
		$headerlen = 12;
	}

	undef @venderItemList;
	undef $venderID;
	undef $venderCID;
	$venderID = $args->{venderID};
	$venderCID = $args->{venderCID} if exists $args->{venderCID};
	my $player = Actor::get($venderID);

	message TF("%s\n" .

		"#   Name                                      Type           Amount       Price\n",
		center(' Vender: ' . $player->nameIdx . ' ', 79, '-')), "list";
	for (my $i = $headerlen; $i < $args->{RAW_MSG_SIZE}; $i+=22) {
		my $item = {};
		my $index;

		($item->{price},
		$item->{amount},
		$index,
		$item->{type},
		$item->{nameID},
		$item->{identified}, # should never happen
		$item->{broken}, # should never happen
		$item->{upgrade},
		$item->{cards})	= unpack('V v2 C v C3 a8', substr($args->{RAW_MSG}, $i, 22));

		$item->{name} = itemName($item);
		$venderItemList[$index] = $item;

		debug("Item added to Vender Store: $item->{name} - $item->{price} z\n", "vending", 2);

		Plugins::callHook('packet_vender_store', {
			venderID => $venderID,
			number => $index,
			name => $item->{name},
			amount => $item->{amount},
			price => $item->{price},
			upgrade => $item->{upgrade},
			cards => $item->{cards},
			type => $item->{type},
			id => $item->{nameID}
		});

		message(swrite(
			"@<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<< @>>>>> @>>>>>>>>>z",
			[$index, $item->{name}, $itemTypes_lut{$item->{type}}, $item->{amount}, formatNumber($item->{price})]),
			"list");
	}
	message("-------------------------------------------------------------------------------\n", "list");

	Plugins::callHook('packet_vender_store2', {
		venderID => $venderID,
		itemList => \@venderItemList
	});
}

sub vender_lost {
	my ($self, $args) = @_;

	my $ID = $args->{ID};
	binRemove(\@venderListsID, $ID);
	delete $venderLists{$ID};
}

sub vender_buy_fail {
	my ($self, $args) = @_;

	my $reason;
	if ($args->{fail} == 1) {
		error TF("Failed to buy %s of item #%s from vender (insufficient zeny).\n", $args->{amount}, $args->{index});
	} elsif ($args->{fail} == 2) {
		error TF("Failed to buy %s of item #%s from vender (overweight).\n", $args->{amount}, $args->{index});
	} else {
		error TF("Failed to buy %s of item #%s from vender (unknown code %s).\n", $args->{amount}, $args->{index}, $args->{fail});
	}
}

sub mail_read {
	my ($self, $args) = @_;

	my $item = {};
	$item->{nameID} = $args->{nameID};
	$item->{upgrade} = $args->{upgrade};
	$item->{cards} = $args->{cards};
	$item->{broken} = $args->{broken};
	$item->{name} = itemName($item);

	my $msg;
	$msg .= center(" " . T("Mail") . " ", 79, '-') . "\n";
	$msg .= swrite(TF("Title: \@%s Sender: \@%s", ('<'x39), ('<'x24)),
			[bytesToString($args->{title}), bytesToString($args->{sender})]);
	$msg .= TF("Message: %s\n", bytesToString($args->{message}));
	$msg .= ("%s\n", ('-'x79));
	$msg .= TF( "Item: %s %s\n" .
				"Zeny: %sz\n",
				$item->{name}, ($args->{amount}) ? "x " . $args->{amount} : "", formatNumber($args->{zeny}));
	$msg .= sprintf("%s\n", ('-'x79));

	message($msg, "info");
}

sub mail_getattachment {
	my ($self, $args) = @_;
	if (!$args->{fail}) {
		message T("Successfully added attachment to inventory.\n"), "info";
	} elsif ($args->{fail} == 2) {
		error T("Failed to get the attachment to inventory due to your weight.\n"), "info";
	} else {
		error T("Failed to get the attachment to inventory.\n"), "info";
	}
}

sub mail_send {
	my ($self, $args) = @_;
	($args->{fail}) ?
		error T("Failed to send mail, the recipient does not exist.\n"), "info" :
		message T("Mail sent succesfully.\n"), "info";
}

sub mail_new {
	my ($self, $args) = @_;
	message TF("New mail from sender: %s titled: %s.\n", bytesToString($args->{sender}), bytesToString($args->{title})), "info";
}


sub mail_delete {
	my ($self, $args) = @_;
	if ($args->{fail}) {
		message TF("Failed to delete mail with ID: %s.\n", $args->{mailID}), "info";
	}
	else {
		message TF("Succeeded to delete mail with ID: %s.\n", $args->{mailID}), "info";
	}
}

sub mail_window {
	my ($self, $args) = @_;
	if ($args->{flag}) {
		message T("Mail window is now closed.\n"), "info";
	}
	else {
		message T("Mail window is now opened.\n"), "info";
	}
}

sub mail_return {
	my ($self, $args) = @_;
	($args->{fail}) ?
		error TF("The mail with ID: %s does not exist.\n", $args->{mailID}), "info" :
		message TF("The mail with ID: %s is returned to the sender.\n", $args->{mailID}), "info";
}

sub premium_rates_info {
	my ($self, $args) = @_;
	message TF("Premium rates: exp %+i%%, death %+i%%, drop %+i%%.\n", $args->{exp}, $args->{death}, $args->{drop}), "info";
}

sub auction_result {
	my ($self, $args) = @_;
	my $flag = $args->{flag};

	if ($flag == 0) {
     	message T("You have failed to bid into the auction.\n"), "info";
	} elsif ($flag == 1) {
		message T("You have successfully bid in the auction.\n"), "info";
	} elsif ($flag == 2) {
		message T("The auction has been canceled.\n"), "info";
	} elsif ($flag == 3) {
		message T("An auction with at least one bidder cannot be canceled.\n"), "info";
	} elsif ($flag == 4) {
		message T("You cannot register more than 5 items in an auction at a time.\n"), "info";
	} elsif ($flag == 5) {
		message T("You do not have enough Zeny to pay the Auction Fee.\n"), "info";
	} elsif ($flag == 6) {
		message T("You have won the auction.\n"), "info";
	} elsif ($flag == 7) {
		message T("You have failed to win the auction.\n"), "info";
	} elsif ($flag == 8) {
		message T("You do not have enough Zeny.\n"), "info";
	} elsif ($flag == 9) {
		message T("You cannot place more than 5 bids at a time.\n"), "info";
	} else {
		warning TF("flag: %s gave unknown results in: %s\n", $args->{flag}, $self->{packet_list}{$args->{switch}}->[0]);
	}
}


sub auction_my_sell_stop {
	my ($self, $args) = @_;
	my $flag = $args->{flag};

	if ($flag == 0) {
     	message T("You have ended the auction.\n"), "info";
	} elsif ($flag == 1) {
		message T("You cannot end the auction.\n"), "info";
	} elsif ($flag == 2) {
		message T("Bid number is incorrect.\n"), "info";
	} else {
		warning TF("flag: %s gave unknown results in: %s\n", $args->{flag}, $self->{packet_list}{$args->{switch}}->[0]);
	}
}

sub auction_windows {
	my ($self, $args) = @_;
	if ($args->{flag}) {
		message T("Auction window is now closed.\n"), "info";
	}
	else {
		message T("Auction window is now opened.\n"), "info";
	}
}

sub auction_add_item {
	my ($self, $args) = @_;
	if ($args->{fail}) {
		message TF("Failed (note: usable items can't be auctioned) to add item with index: %s.\n", $args->{index}), "info";
	}
	else {
		message TF("Succeeded to add item with index: %s.\n", $args->{index}), "info";
	}
}


sub hack_shield_alarm {
	error T("Error: You have been forced to disconnect by a Hack Shield.\n Please check Poseidon.\n"), "connection";
	Commands::run('relog 100000000');
}

sub guild_alliance {
	my ($self, $args) = @_;
	if ($args->{flag} == 0) {
		message T("Already allied.\n"), "info";
	} elsif ($args->{flag} == 1) {
		message T("You rejected the offer.\n"), "info";
	} elsif ($args->{flag} == 2) {
		message T("You accepted the offer.\n"), "info";
	} elsif ($args->{flag} == 3) {
		message T("They have too any alliances\n"), "info";
	} elsif ($args->{flag} == 4) {
		message T("You have too many alliances.\n"), "info";
	} else {
		warning TF("flag: %s gave unknown results in: %s\n", $args->{flag}, $self->{packet_list}{$args->{switch}}->[0]);
	}
}

sub talkie_box {
	my ($self, $args) = @_;
	message TF("%s's talkie box message: %s.\n", Actor::get($args->{ID})->nameString(), $args->{message}), "info";
}

sub manner_message {
	my ($self, $args) = @_;
	if ($args->{flag} == 0) {
		message T("A manner point has been successfully aligned.\n"), "info";
	} elsif ($args->{flag} == 3) {
		message T("Chat Block has been applied by GM due to your ill-mannerous action.\n"), "info";
	} elsif ($args->{flag} == 4) {
		message T("Automated Chat Block has been applied due to Anti-Spam System.\n"), "info";
	} elsif ($args->{flag} == 5) {
		message T("You got a good point.\n"), "info";
	} else {
		warning TF("flag: %s gave unknown results in: %s\n", $args->{flag}, $self->{packet_list}{$args->{switch}}->[0]);
	}
}

sub GM_silence {
	my ($self, $args) = @_;
	if ($args->{flag}) {
		message TF("You have been: muted by %s.\n", bytesToString($args->{name})), "info";
	}
	else {
		message TF("You have been: unmuted by %s.\n", bytesToString($args->{name})), "info";
	}
}

# TODO test if we must use ID to know if the packets are meant for us.
# ID is monsterID
sub taekwon_packets {
	my ($self, $args) = @_;
	my $string = ($args->{value} == 1) ? T("Sun") : ($args->{value} == 2) ? T("Moon") : ($args->{value} == 3) ? T("Stars") : TF("Unknown (%d)", $args->{value});
	if ($args->{flag} == 0) { # Info about Star Gladiator save map: Map registered
		message TF("You have now marked: %s as Place of the %s.\n", bytesToString($args->{name}), $string), "info";
	} elsif ($args->{flag} == 1) { # Info about Star Gladiator save map: Information
		message TF("%s is marked as Place of the %s.\n", bytesToString($args->{name}), $string), "info";
	} elsif ($args->{flag} == 10) { # Info about Star Gladiator hate mob: Register mob
		message TF("You have now marked %s as Target of the %s.\n", bytesToString($args->{name}), $string), "info";
	} elsif ($args->{flag} == 11) { # Info about Star Gladiator hate mob: Information
		message TF("%s is marked as Target of the %s.\n", bytesToString($args->{name}), $string);
	} elsif ($args->{flag} == 20) { #Info about TaeKwon Do TK_MISSION mob
		message TF("[TaeKwon Mission] Target Monster : %s (%d%)"."\n", bytesToString($args->{name}), $args->{value}), "info";
	} elsif ($args->{flag} == 30) { #Feel/Hate reset
		message T("Your Hate and Feel targets have been resetted.\n"), "info";
	} else {
		warning TF("flag: %s gave unknown results in: %s\n", $args->{flag}, $self->{packet_list}{$args->{switch}}->[0]);
	}
}

sub guild_master_member {
	my ($self, $args) = @_;
	if ($args->{type} == 0xd7) {
	} elsif ($args->{type} == 0x57) {
		message T("You are not a guildmaster.\n"), "info";
		return;
	} else {
		warning TF("type: %s gave unknown results in: %s\n", $args->{type}, $self->{packet_list}{$args->{switch}}->[0]);
		return;
	}
	message T("You are a guildmaster.\n"), "info";
}

# 0151
# TODO
sub guild_emblem_img {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 0152
# TODO
sub guild_emblem {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 0156
# TODO
sub guild_member_position_changed {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 01B4
# TODO
sub guild_emblem_update {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 0174
# TODO
sub guild_position_changed {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 0184
# TODO
sub guild_unally {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 0181
# TODO
sub guild_opposition_result {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 0185
# TODO: this packet doesn't exist in eA
sub guild_alliance_added {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 0192
# TODO: add actual functionality, maybe alter field?
sub map_change_cell {
	my ($self, $args) = @_;
	debug "Cell on ($args->{x}, $args->{y}) has been changed to $args->{type} on $args->{map_name}\n", "info";
}

# 01D1

sub blade_stop {
	my ($self, $args) = @_;
	if($args->{active} == 0) {
		message TF("Blade Stop by %s on %s is deactivated.\n", Actor::get($args->{sourceID})->nameString(), Actor::get($args->{targetID})->nameString()), "info";
	} elsif($args->{active} == 1) {
		message TF("Blade Stop by %s on %s is active.\n", Actor::get($args->{sourceID})->nameString(), Actor::get($args->{targetID})->nameString()), "info";
	}
}

sub divorced {
	my ($self, $args) = @_;
	message TF("%s and %s have divorced from each other.\n", $char->{name}, $args->{name}), "info"; # is it $char->{name} or is this packet also used for other players?
}


# 025A
# TODO
sub cooking_list {
	my ($self, $args) = @_;
	undef $cookingList;
	my $k = 0;
	my $msg;
	$msg .= center(" " . T("Cooking List") . " ", 79, '-') . "\n";
	for (my $i = 6; $i < $args->{RAW_MSG_SIZE}; $i += 2) {
		my $nameID = unpack('v', substr($args->{RAW_MSG}, $i, 2));
		$cookingList->[$k] = $nameID;
		$msg .= swrite(sprintf("\@%s \@%s", ('>'x2), ('<'x50)), [$k, itemNameSimple($nameID)]);
		$k++;
	}
	$msg .= sprintf("%s\n", ('-'x79));
	message($msg, "list");
	message T("You can now use the 'cook' command.\n"), "info";
}


sub party_show_picker {
	my ($self, $args) = @_;

	# wtf the server sends this packet for your own character? (rRo)
	return if $args->{sourceID} eq $accountID;

	my $string = ($char->{party}{users}{$args->{sourceID}} && %{$char->{party}{users}{$args->{sourceID}}}) ? $char->{party}{users}{$args->{sourceID}}->name() : $args->{sourceID};
	my $item = {};
	$item->{nameID} = $args->{nameID};
	$item->{identified} = $args->{identified};
	$item->{upgrade} = $args->{upgrade};
	$item->{cards} = $args->{cards};
	$item->{broken} = $args->{broken};
	message TF("Party member %s has picked up item %s.\n", $string, itemName($item)), "info";
}

# 02CB
# TODO
# Required to start the instancing information window on Client
# This window re-appear each "refresh" of client automatically until 02CD is send to client.
sub instance_window_start {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 02CC
# TODO
# To announce Instancing queue creation if no maps available
sub instance_window_queue {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 02CD
# TODO
sub instance_window_join {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}


# 02DC
# TODO
sub battleground_message {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

# 02DD
# TODO
sub battleground_emblem {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
}

sub battleground_score {
	my ($self, $args) = @_;
	message TF("Battleground score - Lions: '%d' VS Eagles: '%d'\n", $args->{score_lion}, $args->{score_eagle}), "info";
}

# 02EF
# TODO
sub font {
	my ($self, $args) = @_;
	debug "Account: $args->{ID} is using fontID: $args->{fontID}\n", "info";
}

# 019E
# TODO
# note: this is probably the trigger for the client's slotmachine effect or so.
sub pet_capture_process {
	my ($self, $args) = @_;
	message T("Attempting to capture pet (slot machine).\n"), "info";
}

# 0294
# TODO -> maybe add table file?
sub book_read {
	my ($self, $args) = @_;
	debug "Reading book: $args->{bookID} page: $args->{page}\n", "info";
}

# TODO can we use itemName($actor)? -> tech: don't think so because it seems that this packet is received before the inventory list
sub rental_time {
	my ($self, $args) = @_;
	message TF("The '%s' item will disappear in %d minutes.\n", itemNameSimple($args->{nameID}), $args->{seconds}/60), "info";
}

# TODO can we use itemName($actor)? -> tech: don't think so because the item might be removed from inventory before this packet is sent -> untested
sub rental_expired {
	my ($self, $args) = @_;
	message TF("Rental item '%s' has expired!\n", itemNameSimple($args->{nameID})), "info";
}

# 0289
# TODO
sub cash_buy_fail {
	my ($self, $args) = @_;
	debug "cash_buy_fail $args->{cash_points} $args->{kafra_points} $args->{fail}\n";
}

sub adopt_reply {
	my ($self, $args) = @_;
	if($args->{type} == 0) {
		message T("You cannot adopt more than 1 child.\n"), "info";
	} elsif($args->{type} == 1) {
		message T("You must be at least character level 70 in order to adopt someone.\n"), "info";
	} elsif($args->{type} == 2) {
		message T("You cannot adopt a married person.\n"), "info";
	}
}

# TODO do something with sourceID, targetID? -> tech: maybe your spouses adopt_request will also display this message for you.
sub adopt_request {
	my ($self, $args) = @_;
	message TF("%s wishes to adopt you. Do you accept?\n", $args->{name}), "info";
	# TODO how to accept?
}

# 0293
sub boss_map_info {
	my ($self, $args) = @_;
	my $bossName = bytesToString($args->{name});

	if ($args->{flag} == 0) {
		message T("You cannot find any trace of a Boss Monster in this area.\n"), "info";
	} elsif ($args->{flag} == 1) {
		message TF("MVP Boss %s is now on location: (%d, %d)\n", $bossName, $args->{x}, $args->{y}), "info";
	} elsif ($args->{flag} == 2) {
		message TF("MVP Boss %s has been detected on this map!\n", $bossName), "info";
	} elsif ($args->{flag} == 3) {
		message TF("MVP Boss %s is dead, but will spawn again in %d hour(s) and %d minutes(s).\n", $bossName, $args->{hours}, $args->{minutes}), "info";
	} else {
		debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) . "\n";
		warning TF("flag: %s gave unknown results in: %s\n", $args->{flag}, $self->{packet_list}{$args->{switch}}->[0]);
	}
}

# 02B1
sub quest_all_list {
	my ($self, $args) = @_;
	$questList = {};
	for (my $i = 8; $i < $args->{amount}*5+8; $i += 5) {
		my ($questID, $active) = unpack('V C', substr($args->{RAW_MSG}, $i, 5));
		$questList->{$questID}->{active} = $active;
		debug "$questID $active\n", "info";
	}
}

# 02B2
# note: this packet shows all quests + their missions and has variable length
sub quest_all_mission {
	my ($self, $args) = @_;
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) ."\n";
	for (my $i = 8; $i < $args->{amount}*104+8; $i += 104) {
		my ($questID, $time_start, $time, $mission_amount) = unpack('V3 v', substr($args->{RAW_MSG}, $i, 14));
		my $quest = \%{$questList->{$questID}};
		$quest->{time_start} = $time_start;
		$quest->{time} = $time;
		debug "$questID $time_start $time $mission_amount\n", "info";
		for (my $j = 0; $j < $mission_amount; $j++) {
			my ($mobID, $count, $mobName) = unpack('V v Z24', substr($args->{RAW_MSG}, 14+$i+$j*30, 30));
			my $mission = \%{$quest->{missions}->{$mobID}};
			$mission->{mobID} = $mobID;
			$mission->{count} = $count;
			$mission->{mobName} = bytesToString($mobName);
			debug "- $mobID $count $mobName\n", "info";
		}
	}
}

# 02B3
# note: this packet shows all missions for 1 quest and has fixed length
sub quest_add {
	my ($self, $args) = @_;
	my $questID = $args->{questID};
	my $quest = \%{$questList->{$questID}};

	unless (%$quest) {
		message TF("Quest: %s has been added.\n", $quests_lut{$questID} ? "$quests_lut{$questID}{title} ($questID)" : $questID), "info";
	}

	$quest->{time_start} = $args->{time_start};
	$quest->{time} = $args->{time};
	$quest->{active} = $args->{active};
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) ."\n";
	for (my $i = 0; $i < $args->{amount}; $i++) {
		my ($mobID, $count, $mobName) = unpack('V v Z24', substr($args->{RAW_MSG}, 17+$i*30, 30));
		my $mission = \%{$quest->{missions}->{$mobID}};
		$mission->{mobID} = $mobID;
		$mission->{count} = $count;
		$mission->{mobName} = bytesToString($mobName);
		debug "- $mobID $count $mobName\n", "info";
	}
}

# 02B4
sub quest_delete {
	my ($self, $args) = @_;
	my $questID = $args->{questID};
	message TF("Quest: %s has been deleted.\n", $quests_lut{$questID} ? "$quests_lut{$questID}{title} ($questID)" : $questID), "info";
	delete $questList->{$questID};
}


# 02B7
sub quest_active {
	my ($self, $args) = @_;
	my $questID = $args->{questID};

	message $args->{active}
		? TF("Quest %s is now active.\n", $quests_lut{$questID} ? "$quests_lut{$questID}{title} ($questID)" : $questID)
		: TF("Quest %s is now inactive.\n", $quests_lut{$questID} ? "$quests_lut{$questID}{title} ($questID)" : $questID)
	, "info";

	$questList->{$args->{questID}}->{active} = $args->{active};
}

# 018B
sub quit_response {
	my ($self, $args) = @_;
	if ($args->{fail}) { # NOTDISCONNECTABLE_STATE =  0x1
		error T("Please wait 10 seconds before trying to log out.\n"); # MSI_CANT_EXIT_NOW =  0x1f6
	} else { # DISCONNECTABLE_STATE =  0x0
		message T("Logged out from the server succesfully.\n"), "success";
	}
}

sub GM_req_acc_name {
	my ($self, $args) = @_;
	message TF("The accountName for ID %s is %s.\n", $args->{targetID}, $args->{accountName}), "info";
}

# 00CB
sub sell_result {
	my ($self, $args) = @_;
	if ($args->{fail}) {
		error T("Sell failed.\n");
	} else {
		message T("Sell completed.\n"), "success";
	}
}

use constant QTYPE => (
	0x0 => [0xff, 0xff, 0, 0],
	0x1 => [0xff, 0x80, 0, 0],
	0x2 => [0, 0xff, 0, 0],
	0x3 => [0x80, 0, 0x80, 0],
);


sub parse_minimap_indicator {
	my ($self, $args) = @_;

	$args->{actor} = Actor::get($args->{npcID});
	$args->{show} = $args->{type} != 2;

	unless (defined $args->{red}) {
		@{$args}{qw(red green blue alpha)} = @{{QTYPE}->{$args->{qtype}} || [0xff, 0xff, 0xff, 0]};
	}

	# FIXME: packet 0144: coordinates are missing now when clearing indicators; ID is used
	# Wx depends on coordinates there
}

sub account_payment_info {
	my ($self, $args) = @_;
	my $D_minute = $args->{D_minute};
	my $H_minute = $args->{H_minute};

	my $D_d = int($D_minute / 1440);
	my $D_h = int(($D_minute % 1440) / 60);
	my $D_m = int(($D_minute % 1440) % 60);

	my $H_d = int($H_minute / 1440);
	my $H_h = int(($H_minute % 1440) / 60);
	my $H_m = int(($H_minute % 1440) % 60);

	message  T("============= Account payment information =============\n"), "info";
	message TF("Pay per day  : %s day(s) %s hour(s) and %s minute(s)\n", $D_d, $D_h, $D_m), "info";
	message TF("Pay per hour : %s day(s) %s hour(s) and %s minute(s)\n", $H_d, $H_h, $H_m), "info";
	message  "-------------------------------------------------------\n", "info";
}

# TODO
sub reconstruct_minimap_indicator {
}

use constant {
	HO_PRE_INIT => 0x0,
	HO_RELATIONSHIP_CHANGED => 0x1,
	HO_FULLNESS_CHANGED => 0x2,
	HO_ACCESSORY_CHANGED => 0x3,
	HO_HEADTYPE_CHANGED => 0x4,
};

# 0230
# TODO: what is type?
sub homunculus_info {
	my ($self, $args) = @_;
	debug "homunculus_info type: $args->{type}\n", "homunculus";
	if ($args->{state} == HO_PRE_INIT) {
		my $state = $char->{homunculus}{state}
			if ($char->{homunculus} && $char->{homunculus}{ID} && $char->{homunculus}{ID} ne $args->{ID});
		$char->{homunculus} = Actor::get($args->{ID}) if ($char->{homunculus}{ID} ne $args->{ID});
		$char->{homunculus}{state} = $state if (defined $state);
		$char->{homunculus}{map} = $field->baseName;
		unless ($char->{slaves}{$char->{homunculus}{ID}}) {
			AI::SlaveManager::addSlave ($char->{homunculus});
		}
	} elsif ($args->{state} == HO_RELATIONSHIP_CHANGED) {
		$char->{homunculus}{intimacy} = $args->{val} if $char->{homunculus};
	} elsif ($args->{state} == HO_FULLNESS_CHANGED) {
		$char->{homunculus}{hunger} = $args->{val} if $char->{homunculus};
	} elsif ($args->{state} == HO_ACCESSORY_CHANGED) {
		$char->{homunculus}{accessory} = $args->{val} if $char->{homunculus};
	} elsif ($args->{state} == HO_HEADTYPE_CHANGED) {
		#
	}
}

##
# minimap_indicator({bool show, Actor actor, int x, int y, int red, int green, int blue, int alpha [, int effect]})
# show: whether indicator is shown or cleared
# actor: @MODULE(Actor) who issued the indicator; or which Actor it's binded to
# x, y: indicator coordinates
# red, green, blue, alpha: indicator color
# effect: unknown, may be missing
#
# Minimap indicator.
sub minimap_indicator {
	my ($self, $args) = @_;

	my $color_str = "[R:$args->{red}, G:$args->{green}, B:$args->{blue}, A:$args->{alpha}]";
	my $indicator = T("minimap indicator");
	if (defined $args->{type}) {
		unless ($args->{type} == 1 || $args->{type} == 2) {
			$indicator .= TF(" (unknown type %d)", $args->{type});
		}
	} elsif (defined $args->{effect}) {
		if ($args->{effect} == 1) {
			$indicator = T("*Quest!*");
		} elsif ($args->{effect}) { # 0 is no effect
			$indicator = TF("unknown effect %d", $args->{effect});
		}
	}

	if ($args->{show}) {
		message TF("%s shown %s at location %d, %d " .
		"with the color %s\n", $args->{actor}, $indicator, @{$args}{qw(x y)}, $color_str),
		'effect';
	} else {
		message TF("%s cleared %s at location %d, %d " .
		"with the color %s\n", $args->{actor}, $indicator, @{$args}{qw(x y)}, $color_str),
		'effect';
	}
}

sub local_broadcast {
	my ($self, $args) = @_;
	my $message = bytesToString($args->{message});
	my $color = uc(sprintf("%06x", $args->{color})); # hex code
	stripLanguageCode(\$message);
	chatLog("lb", "$message\n");# if ($config{logLocalBroadcast});
	message "$message\n", "schat";
	Plugins::callHook('packet_localBroadcast', {
		Msg => $message,
		color => $color
	});
}

sub parse_sage_autospell {
	my ($self, $args) = @_;

	$args->{skills} = [map { Skill->new(idn => $_) } sort { $a<=>$b } grep {$_}
		exists $args->{autoshadowspell_list}
		? (unpack 'v*', $args->{autoshadowspell_list})
		: (unpack 'V*', $args->{autospell_list})
	];
}

sub reconstruct_sage_autospell {
	my ($self, $args) = @_;

	my @skillIDs = map { $_->getIDN } $args->{skills};
	$args->{autoshadowspell_list} = pack 'v*', @skillIDs;
	$args->{autospell_list} = pack 'V*', @skillIDs;
}

##
# sage_autospell({arrayref skills, int why})
# skills: list of @MODULE(Skill) instances
# why: unknown
#
# Skill list for Sage's Hindsight and Shadow Chaser's Auto Shadow Spell.
sub sage_autospell {
	my ($self, $args) = @_;

	return unless $self->changeToInGameState;

	my $msg = center(' ' . T('Auto Spell') . ' ', 40, '-') . "\n"
	. T("   # Skill\n")
	. (join '', map { swrite '@>>> @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<', [$_->getIDN, $_] } @{$args->{skills}})
	. ('-'x40) . "\n";

	message $msg, 'list';

	if ($config{autoSpell}) {
		my $skill = new Skill(auto => $config{autoSpell});
		if (!$config{autoSpell_safe} || List::Util::first { $_->getIDN == $skill->getIDN } @{$args->{skills}}) {
			if (defined $args->{why}) {
				$messageSender->sendSkillSelect($skill->getIDN, $args->{why});
			} else {
				$messageSender->sendAutoSpell($skill->getIDN);
			}
		} else {
			error TF("Configured autoSpell (%s) is not available.\n", $skill);
			message T("Disable autoSpell_safe to use it anyway.\n"), 'hint';
		}
	} else {
		message T("Configure autoSpell to automatically select skill for Auto Spell.\n"), 'hint';
	}
}

sub show_eq {
	my ($self, $args) = @_;

	my $jump = 26;

	my $unpack_string  = "v ";
	   $unpack_string .= "v C2 v v C2 ";
	   $unpack_string .= "a8 ";
	   $unpack_string .= "a6"; #unimplemented in eA atm

	if (exists $args->{robe}) {  # check packet version
		$unpack_string .= "v "; # ??
		$jump += 2;
	}

	for (my $i = 0; $i < length($args->{equips_info}); $i += $jump) {
		my ($index,
			$ID, $type, $identified, $type_equip, $equipped, $broken, $upgrade, # typical for nonstackables
			$cards,
			$expire) = unpack($unpack_string, substr($args->{equips_info}, $i));

		my $item = {};
		$item->{index} = $index;

		$item->{nameID} = $ID;
		$item->{type} = $type;

		$item->{identified} = $identified;
		$item->{type_equip} = $type_equip;
		$item->{equipped} = $equipped;
		$item->{broken} = $broken;
		$item->{upgrade} = $upgrade;

		$item->{cards} = $cards;

		$item->{expire} = $expire;

		message sprintf("%-20s: %s\n", $equipTypes_lut{$item->{equipped}}, itemName($item)), "list";
		debug "$index, $ID, $type, $identified, $type_equip, $equipped, $broken, $upgrade, $cards, $expire\n";
	}
}

sub show_eq_msg_other {
	my ($self, $args) = @_;
	if ($args->{flag}) {
		message T("Allowed to view the other player's Equipment.\n");
	} else {
		message T("Not allowed to view the other player's Equipment.\n");
	}
}

sub show_eq_msg_self {
	my ($self, $args) = @_;
	if ($args->{type}) {
		message T("Other players are allowed to view your Equipment.\n");
	} else {
		message T("Other players are not allowed to view your Equipment.\n");
	}
}

# 043D
sub skill_post_delay {
	my ($self, $args) = @_;

	my $skillName = (new Skill(idn => $args->{ID}))->getName;
	my $status = defined $statusName{'EFST_DELAY'} ? $statusName{'EFST_DELAY'} : 'Delay';

	$char->setStatus($skillName." ".$status, 1, $args->{time});
}

# TODO: known prefixes (chat domains): micc | ssss | blue | tool
# micc = micc<24 characters, this is the sender name. seems like it's null padded><hex color code><message>
# micc = Player Broadcast   The struct: micc<23bytes player name+some hex><\x00><colour code><full message>
# The first player name is used for detecting the player name only according to the disassembled client.
# The full message contains the player name at the first 22 bytes
# TODO micc.* is currently unstricted, however .{24} and .{23} do not detect chinese with some reasons, please improve this regex if necessary
sub system_chat {
	my ($self, $args) = @_;
	my $message = bytesToString($args->{message});
	my $prefix;
	my $color;
	if ($message =~ s/^ssss//g) {  # forces color yellow, or WoE indicator?
		$prefix = T('[WoE]');
	} elsif ($message =~ /^micc.{12,24}([0-9a-fA-F]{6})(.*)/) {
		($color, $message) = $message =~ /^micc.*([0-9a-fA-F]{6})(.*)/;
		$prefix = T('[S]');
	} elsif ($message =~ s/^blue//g) {  # forces color blue
		$prefix = T('[S]');
	} elsif ($message =~ /^tool([0-9a-fA-F]{6})(.*)/) {
		($color, $message) = $message =~ /^tool([0-9a-fA-F]{6})(.*)/;
		$prefix = T('[S]');
	} else {
		$prefix = T('[S]');
	}
	$message =~ s/\000//g; # remove null charachters
	$message =~ s/^ +//g; $message =~ s/ +$//g; # remove whitespace in the beginning and the end of $message
	stripLanguageCode(\$message);
	chatLog("s", "$message\n") if ($config{logSystemChat});
	# Translation Comment: System/GM chat
	message TF("%s %s\n", $prefix, $message), "schat";
	ChatQueue::add('gm', undef, undef, $message);

	Plugins::callHook('packet_sysMsg', {
		Msg => $message,
		MsgColor => $color,
		MsgUser => undef # TODO: implement this value, we can get this from "micc" messages by regex.
	});
}

sub warp_portal_list {
	my ($self, $args) = @_;

	# strip gat extension
	($args->{memo1}) = $args->{memo1} =~ /^(.*)\.gat/;
	($args->{memo2}) = $args->{memo2} =~ /^(.*)\.gat/;
	($args->{memo3}) = $args->{memo3} =~ /^(.*)\.gat/;
	($args->{memo4}) = $args->{memo4} =~ /^(.*)\.gat/;
	# Auto-detect saveMap
	if ($args->{type} == 26) {
		configModify('saveMap', $args->{memo2}) if ($args->{memo2} && $config{'saveMap'} ne $args->{memo2});
	} elsif ($args->{type} == 27) {
		configModify('saveMap', $args->{memo1}) if ($args->{memo1} && $config{'saveMap'} ne $args->{memo1});
	}

	$char->{warp}{type} = $args->{type};
	undef @{$char->{warp}{memo}};
	push @{$char->{warp}{memo}}, $args->{memo1} if $args->{memo1} ne "";
	push @{$char->{warp}{memo}}, $args->{memo2} if $args->{memo2} ne "";
	push @{$char->{warp}{memo}}, $args->{memo3} if $args->{memo3} ne "";
	push @{$char->{warp}{memo}}, $args->{memo4} if $args->{memo4} ne "";

	message T("----------------- Warp Portal --------------------\n" .
		"#  Place                           Map\n"), "list";
	for (my $i = 0; $i < @{$char->{warp}{memo}}; $i++) {
		message(swrite(
			"@< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<",
			[$i, $maps_lut{$char->{warp}{memo}[$i].'.rsw'},
			$char->{warp}{memo}[$i]]),
			"list");
	}
	message("--------------------------------------------------\n", "list");
	unless ($taskManager->isMutexActive('teleport')) {
		debug "Cancelling unwanted teleport window \n", "teleport";
		$messageSender->sendWarpTele(27, 'cancel'); 
	}
}


# 0828,14
sub char_delete2_result {
	my ($self, $args) = @_;
	my $result = $args->{result};
	my $deleteDate = $args->{deleteDate};

	if ($result && $deleteDate) {
		$deleteDate = getFormattedDate($deleteDate);

		message TF("Your character will be delete, left %s\n", $deleteDate), "connection";
		$chars[$messageSender->{char_delete_slot}]{deleteDate} = $deleteDate;
	} elsif ($result == 0) {
		error T("That character already planned to be erased!\n");
	} elsif ($result == 3) {
		error T("Error in database of the server!\n");
	} elsif ($result == 4) {
		error T("To delete a character you must withdraw from the guild!\n");
	} elsif ($result == 5) {
		error T("To delete a character you must withdraw from the party!\n");
	} else {
		error TF("Unknown error when trying to delete the character! (Error number: %s)\n", $result);
	}

	charSelectScreen;
}

# 082C,14
sub char_delete2_cancel_result {
	my ($self, $args) = @_;
	my $result = $args->{result};

	if ($result) {
		message T("Character is no longer scheduled to be deleted\n"), "connection";
		$chars[$messageSender->{char_delete_slot}]{deleteDate} = '';
	} elsif ($result == 2) {
		error T("Error in database of the server!\n");
	} else {
		error TF("Unknown error when trying to cancel the deletion of the character! (Error number: %s)\n", $result);
	}

	charSelectScreen;
}

# 013C
sub arrow_equipped {
	my ($self, $args) = @_;
	return unless changeToInGameState();
	return unless $args->{index};
	$char->{arrow} = $args->{index};

	my $item = $char->inventory->getByServerIndex($args->{index});
	if ($item && $char->{equipment}{arrow} != $item) {
		$char->{equipment}{arrow} = $item;
		$item->{equipped} = 32768;
		$ai_v{temp}{waitForEquip}-- if $ai_v{temp}{waitForEquip};
		message TF("Arrow/Bullet equipped: %s (%d) x %s\n", $item->{name}, $item->{invIndex}, $item->{amount});
	}
}

# 00AF, 07FA
sub inventory_item_removed {
	my ($self, $args) = @_;
	return unless changeToInGameState();
	my $item = $char->inventory->getByServerIndex($args->{index});
	my $reason = $args->{reason};

	if ($reason) {
		if ($reason == 1) {
			debug TF("%s was used to cast the skill\n", $item->{name}), "inventory", 1;
		} elsif ($reason == 2) {
			debug TF("%s broke due to the refinement failed\n", $item->{name}), "inventory", 1;
		} elsif ($reason == 3) {
			debug TF("%s used in a chemical reaction\n", $item->{name}), "inventory", 1;
		} elsif ($reason == 4) {
			debug TF("%s was moved to the storage\n", $item->{name}), "inventory", 1;
		} elsif ($reason == 5) {
			debug TF("%s was moved to the cart\n", $item->{name}), "inventory", 1;
		} elsif ($reason == 6) {
			debug TF("%s was sold\n", $item->{name}), "inventory", 1;
		} elsif ($reason == 7) {
			debug TF("%s was consumed by Four Spirit Analysis skill\n", $item->{name}), "inventory", 1;
		} else {
			debug TF("%s was consumed by an unknown reason (reason number %s)\n", $item->{name}, $reason), "inventory", 1;
		}
	}

	if ($item) {
		inventoryItemRemoved($item->{invIndex}, $args->{amount});
		Plugins::callHook('packet_item_removed', {index => $item->{invIndex}});
	}
}

# 012B
sub cart_off {
	undef $cart{exists};
	message T("Cart released.\n"), "success";
}

# 012D
sub shop_skill {
	my ($self, $args) = @_;

	# Used the shop skill.
	my $number = $args->{number};
	message TF("You can sell %s items!\n", $number);
}

# 01D0 (spirits), 01E1 (coins), 08CF (amulets)
sub revolving_entity {
	my ($self, $args) = @_;

	# Monk Spirits or Gunslingers' coins or senior ninja
	my $sourceID = $args->{sourceID};
	my $entityNum = $args->{entity};
	my $entityElement = $elements_lut{$args->{type}} if ($args->{type} && $entityNum);
	my $entityType;

	my $actor = Actor::get($sourceID);
	if ($args->{switch} eq '01D0') {
		# Translation Comment: Spirit sphere of the monks
		$entityType = T('spirit');
	} elsif ($args->{switch} eq '01E1') {
		# Translation Comment: Coin of the gunslinger
		$entityType = T('coin');
	} elsif ($args->{switch} eq '08CF') {
		# Translation Comment: Amulet of the warlock
		$entityType = T('amulet');
	} else {
		$entityType = T('entity unknown');
	}

	if ($sourceID eq $accountID && $entityNum != $char->{spirits}) {
		$char->{spirits} = $entityNum;
		$char->{amuletType} = $entityElement;
		$entityElement ?
			# Translation Comment: Message displays following: quantity, the name of the entity and its element
			message TF("You have %s %s(s) of %s now\n", $entityNum, $entityType, $entityElement), "parseMsg_statuslook", 1 :
			# Translation Comment: Message displays following: quantity and the name of the entity
			message TF("You have %s %s(s) now\n", $entityNum, $entityType), "parseMsg_statuslook", 1;
	} elsif ($entityNum != $actor->{spirits}) {
		$actor->{spirits} = $entityNum;
		$actor->{amuletType} = $entityElement;
		$entityElement ?
			# Translation Comment: Message displays following: actor, quantity, the name of the entity and its element
			message TF("%s has %s %s(s) of %s now\n", $actor, $entityNum, $entityType, $entityElement), "parseMsg_statuslook", 1 :
			# Translation Comment: Message displays following: actor, quantity and the name of the entity
			message TF("%s has %s %s(s) now\n", $actor, $entityNum, $entityType), "parseMsg_statuslook", 1;
	}
}

# 0977
sub monster_hp_info {
	my ($self, $args) = @_;
	my $monster = $monstersList->getByID($args->{ID});
	if ($monster) {
		$monster->{hp} = $args->{hp};
		$monster->{hp_max} = $args->{hp_max};

		debug TF("Monster %s has hp %s/%s (%s%)\n", $monster->name, $monster->{hp}, $monster->{hp_max}, $monster->{hp} * 100 / $monster->{hp_max}), "parseMsg_damage";
	}
}

##
# account_id({accountID})
#
# This is for what eA calls PacketVersion 9, they send the AID in a 'proper' packet
sub account_id {
	my ($self, $args) = @_;
	# the account ID is already unpacked into PLAIN TEXT when it gets to this function...
	# So lets not fuckup the $accountID since we need that later... someone will prolly have to fix this later on
	my $accountID = $args->{accountID};
	debug sprintf("Account ID: %s (%s)\n", unpack('V',$accountID), getHex($accountID));
}

##
# marriage_partner_name({String name})
#
# Name of the partner character, sent to everyone around right before casting "I miss you".
sub marriage_partner_name {
	my ($self, $args) = @_;

	message TF("Marriage partner name: %s\n", $args->{name});
}

sub login_pin_code_request {
	# This is ten second-level password login for 2013/3/29 upgrading of twRO
	my ($self, $args) = @_;
	# flags:
	# 0 - correct
	# 1 - requested (already defined)
	# 2 - requested (not defined)
	# 3 - expired
	# 5 - invalid (official servers?)
	# 7 - disabled?
	# 8 - incorrect
	if ($args->{flag} == 0) { # removed check for seed 0, eA/rA/brA sends a normal seed.
		message T("PIN code is correct.\n"), "success";
		# call charSelectScreen
		if (charSelectScreen(1) == 1) {
			$firstLoginMap = 1;
			$startingzeny = $chars[$config{'char'}]{'zeny'} unless defined $startingzeny;
			$sentWelcomeMessage = 1;
		}
	} elsif ($args->{flag} == 1) {
		# PIN code query request.
		$accountID = $args->{accountID};
		debug sprintf("Account ID: %s (%s)\n", unpack('V',$accountID), getHex($accountID));

		message T("Server requested PIN password in order to select your character.\n"), "connection";
		return if ($config{loginPinCode} eq '' && !($self->queryAndSaveLoginPinCode()));
		$messageSender->sendLoginPinCode($args->{seed}, 0);
	} elsif ($args->{flag} == 2) {
		# PIN code has never been set before, so set it.
		warning T("PIN password is not set for this account.\n"), "connection";
		return if ($config{loginPinCode} eq '' && !($self->queryAndSaveLoginPinCode()));

		while ((($config{loginPinCode} =~ /[^0-9]/) || (length($config{loginPinCode}) != 4)) &&
		  !($self->queryAndSaveLoginPinCode("Your PIN should never contain anything but exactly 4 numbers.\n"))) {
			error T("Your PIN should never contain anything but exactly 4 numbers.\n");
		}
		$messageSender->sendLoginPinCode($args->{seed}, 1);
	} elsif ($args->{flag} == 3) {
		# should we use the same one again? is it possible?
		warning T("PIN password expired.\n"), "connection";
		return if ($config{loginPinCode} eq '' && !($self->queryAndSaveLoginPinCode()));

		while ((($config{loginPinCode} =~ /[^0-9]/) || (length($config{loginPinCode}) != 4)) &&
		  !($self->queryAndSaveLoginPinCode("Your PIN should never contain anything but exactly 4 numbers.\n"))) {
			error T("Your PIN should never contain anything but exactly 4 numbers.\n");
		}
		$messageSender->sendLoginPinCode($args->{seed}, 1);
	} elsif ($args->{flag} == 5) {
		# PIN code invalid.
		error T("PIN code is invalid, don't use sequences or repeated numbers.\n");
		# configModify('loginPinCode', '', 1);
		return if (!($self->queryAndSaveLoginPinCode(T("The login PIN code that you entered is invalid. Please re-enter your login PIN code."))));
		$messageSender->sendLoginPinCode($args->{seed}, 0);
	} elsif ($args->{flag} == 7) {
		# PIN code disabled.
		$accountID = $args->{accountID};
		debug sprintf("Account ID: %s (%s)\n", unpack('V',$accountID), getHex($accountID));

		# call charSelectScreen
		$self->{lockCharScreen} = 0;
		if (charSelectScreen(1) == 1) {
			$firstLoginMap = 1;
			$startingzeny = $chars[$config{'char'}]{'zeny'} unless defined $startingzeny;
			$sentWelcomeMessage = 1;
		}
	} elsif ($args->{flag} == 8) {
		# PIN code incorrect.
		error T("PIN code is incorrect.\n");
		#configModify('loginPinCode', '', 1);
		return if (!($self->queryAndSaveLoginPinCode(T("The login PIN code that you entered is incorrect. Please re-enter your login PIN code."))));
		$messageSender->sendLoginPinCode($args->{seed}, 0);
	} else {
		debug("login_pin_code_request: unknown flag $args->{flag}\n");
	}

	$timeout{master}{time} = time;
}

sub login_pin_new_code_result {
	my ($self, $args) = @_;

	if ($args->{flag} == 2) {
		# PIN code invalid.
		error T("PIN code is invalid, don't use sequences or repeated numbers.\n");
		#configModify('loginPinCode', '', 1);
		return if (!($self->queryAndSaveLoginPinCode(T("PIN code is invalid, don't use sequences or repeated numbers.\n"))));

		# there's a bug in bRO where you can use letters or symbols or even a string as your PIN code.
		# as a result this will render you unable to login again (forever?) using the official client
		# and this is detectable and can result in a permanent ban. we're using this code in order to
		# prevent this. - revok 17.12.2012
		while ((($config{loginPinCode} =~ /[^0-9]/) || (length($config{loginPinCode}) != 4)) &&
			!($self->queryAndSaveLoginPinCode("Your PIN should never contain anything but exactly 4 numbers.\n"))) {
			error T("Your PIN should never contain anything but exactly 4 numbers.\n");
		}

		$messageSender->sendLoginPinCode($args->{seed}, 0);
	}
}

#08FF
sub actor_status_active2 {
	my ($self, $args) = @_;
	return unless Network::Receive::changeToInGameState();
	my ($type, $ID, $tick, $unknown1, $unknown2, $unknown3) = @{$args}{qw(type ID tick unknown1 unknown2 unknown3)};
	my $status = defined $statusHandle{$type} ? $statusHandle{$type} : "UNKNOWN_STATUS_$type";
	$cart{type} = $unknown1 if ($type == 673 && defined $unknown1 && ($ID eq $accountID)); # for Cart active
	$args->{skillName} = defined $statusName{$status} ? $statusName{$status} : $status;
	($args->{actor} = Actor::get($ID))->setStatus($status, 1, $tick == 9999 ? undef : $tick, $args->{unknown1});
}


#099B
sub map_property3 {
	my ($self, $args) = @_;

	if($config{'status_mapType'}){
		$char->setStatus(@$_) for map {[$_->[1], $args->{type} == $_->[0]]}
		grep { $args->{type} == $_->[0] || $char->{statuses}{$_->[1]} }
		map {[$_, defined $mapTypeHandle{$_} ? $mapTypeHandle{$_} : "UNKNOWN_MAPTYPE_$_"]}
		0 .. List::Util::max $args->{type}, keys %mapTypeHandle;
	}

	$pvp = {6 => 1, 8 => 2, 19 => 3}->{$args->{type}};
	if ($pvp) {
		Plugins::callHook('pvp_mode', {
			pvp => $pvp # 1 PvP, 2 GvG, 3 Battleground
		});
	}
}

#099F
sub area_spell_multiple2 {
	my ($self, $args) = @_;

	# Area effect spells; including traps!
	my $len = $args->{len} - 4;
	my $spellInfo = $args->{spellInfo};
	my $msg = "";
	my $binID;
	my ($ID, $sourceID, $x, $y, $type, $range, $fail);
	for (my $i = 0; $i < $len; $i += 18) {
		$msg = substr($spellInfo, $i, 18);
		($ID, $sourceID, $x, $y, $type, $range, $fail) = unpack('a4 a4 v3 X2 C2', $msg);

		if ($spells{$ID} && $spells{$ID}{'sourceID'} eq $sourceID) {
			$binID = binFind(\@spellsID, $ID);
			$binID = binAdd(\@spellsID, $ID) if ($binID eq "");
		} else {
			$binID = binAdd(\@spellsID, $ID);
		}
	
		$spells{$ID}{'sourceID'} = $sourceID;
		$spells{$ID}{'pos'}{'x'} = $x;
		$spells{$ID}{'pos'}{'y'} = $y;
		$spells{$ID}{'pos_to'}{'x'} = $x;
		$spells{$ID}{'pos_to'}{'y'} = $y;
		$spells{$ID}{'binID'} = $binID;
		$spells{$ID}{'type'} = $type;
		if ($type == 0x81) {
			message TF("%s opened Warp Portal on (%d, %d)\n", getActorName($sourceID), $x, $y), "skill";
		}
		debug "Area effect ".getSpellName($type)." ($binID) from ".getActorName($sourceID)." appeared on ($x, $y)\n", "skill", 2;
	}

	Plugins::callHook('packet_areaSpell', {
		fail => $fail,
		sourceID => $sourceID,
		type => $type,
		x => $x,
		y => $y
	});
}

sub sync_request_ex {
	my ($self, $args) = @_;
	
	# Debug Log
	# message "Received Sync Ex : 0x" . $args->{switch} . "\n";
	
	# Computing Sync Ex - By Fr3DBr
	my $PacketID = $args->{switch};
	
	# Getting Sync Ex Reply ID from Table
	my $SyncID = $self->{sync_ex_reply}->{$PacketID};
	
	# Cleaning Leading Zeros
	$PacketID =~ s/^0+//;	
	
	# Cleaning Leading Zeros	
	$SyncID =~ s/^0+//;
	
	# Debug Log
	#error sprintf("Received Ex Packet ID : 0x%s => 0x%s\n", $PacketID, $SyncID);

	# Converting ID to Hex Number
	$SyncID = hex($SyncID);

	# Dispatching Sync Ex Reply
	$messageSender->sendReplySyncRequestEx($SyncID);
}

sub cash_shop_list {
	my ($self, $args) = @_;
	my $tabcode = $args->{tabcode};
	my $jump = 6;
	my $unpack_string  = "v V";
	# CASHSHOP_TAB_NEW => 0x0,
	# CASHSHOP_TAB_POPULAR => 0x1,
	# CASHSHOP_TAB_LIMITED => 0x2,
	# CASHSHOP_TAB_RENTAL => 0x3,
	# CASHSHOP_TAB_PERPETUITY => 0x4,
	# CASHSHOP_TAB_BUFF => 0x5,
	# CASHSHOP_TAB_RECOVERY => 0x6,
	# CASHSHOP_TAB_ETC => 0x7
	# CASHSHOP_TAB_MAX => 8
	my %cashitem_tab = (
		0 => 'New',
		1 => 'Popular',
		2 => 'Limited',
		3 => 'Rental',
		4 => 'Perpetuity',
		5 => 'Buff',
		6 => 'Recovery',
		7 => 'Etc',
	);
	debug TF("%s\n" .
		"#   Name                               Price\n",
		center(' Tab: ' . $cashitem_tab{$tabcode} . ' ', 44, '-')), "list";
	for (my $i = 0; $i < length($args->{itemInfo}); $i += $jump) {
		my ($ID, $price) = unpack($unpack_string, substr($args->{itemInfo}, $i));
		my $name = itemNameSimple($ID);
		push(@{$cashShop{list}[$tabcode]}, {item_id => $ID, price => $price}); # add to cashshop
		debug(swrite(
			"@<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @>>>>>>C",
			[$i, $name, formatNumber($price)]),
			"list");

		}
}

sub cash_shop_open_result {
	my ($self, $args) = @_;
	#'0845' => ['cash_window_shop_open', 'v2', [qw(cash_points kafra_points)]],
	message TF("Cash Points: %sC - Kafra Points: %sC\n", formatNumber ($args->{cash_points}), formatNumber ($args->{kafra_points}));
	$cashShop{points} = {
							cash => $args->{cash_points},
							kafra => $args->{kafra_points}
						};
}

sub cash_shop_buy_result {
	my ($self, $args) = @_;
		# TODO: implement result messages:
		# SUCCESS			= 0x0,
		# WRONG_TAB?		= 0x1, // we should take care with this, as it's detectable by the server
		# SHORTTAGE_CASH		= 0x2,
		# UNKONWN_ITEM		= 0x3,
		# INVENTORY_WEIGHT		= 0x4,
		# INVENTORY_ITEMCNT		= 0x5,
		# RUNE_OVERCOUNT		= 0x9,
		# EACHITEM_OVERCOUNT		= 0xa,
		# UNKNOWN			= 0xb,
	if ($args->{result} > 0) {
		error TF("Error while buying %s from cash shop. Error code: %s\n", itemNameSimple($args->{item_id}), $args->{result});
	} else {
		message TF("Bought %s from cash shop. Current CASH: %s\n", itemNameSimple($args->{item_id}), formatNumber($args->{updated_points})), "success";
		$cashShop{points}->{cash} = $args->{updated_points};
	}
	
	debug sprintf("Got result ID [%s] while buying %s from CASH Shop. Current CASH: %s \n", $args->{result}, itemNameSimple($args->{item_id}), formatNumber($args->{updated_points}));

	
}

sub player_equipment {
	my ($self, $args) = @_;

	my ($sourceID, $type, $ID1, $ID2) = @{$args}{qw(sourceID type ID1 ID2)};
	my $player = ($sourceID ne $accountID)? $playersList->getByID($sourceID) : $char;
	return unless $player;

	if ($type == 0) {
		# Player changed job
		$player->{jobID} = $ID1;

	} elsif ($type == 2) {
		if ($ID1 ne $player->{weapon}) {
			message TF("%s changed Weapon to %s\n", $player, itemName({nameID => $ID1})), "parseMsg_statuslook", 2;
			$player->{weapon} = $ID1;
		}
		if ($ID2 ne $player->{shield}) {
			message TF("%s changed Shield to %s\n", $player, itemName({nameID => $ID2})), "parseMsg_statuslook", 2;
			$player->{shield} = $ID2;
		}
	} elsif ($type == 3) {
		$player->{headgear}{low} = $ID1;
	} elsif ($type == 4) {
		$player->{headgear}{top} = $ID1;
	} elsif ($type == 5) {
		$player->{headgear}{mid} = $ID1;
	} elsif ($type == 9) {
		if ($player->{shoes} && $ID1 ne $player->{shoes}) {
			message TF("%s changed Shoes to: %s\n", $player, itemName({nameID => $ID1})), "parseMsg_statuslook", 2;
		}
		$player->{shoes} = $ID1;
	}
}


sub disconnect_character {
	my ($self, $args) = @_;
	debug "disconnect_character result: $args->{result}\n";
}

sub character_block_info {
	#TODO
}

1;

#!/usr/bin/perl
#-------------------------------------------------------------------------------
# Start a spot instance on EC2 using the user's latest Amazon Machine Image snap
# shot more conveniently than using the EC2 console each time.
# Philip R Brenan at gmail dot com, Appa Apps Ltd, 2016
#-------------------------------------------------------------------------------

use warnings FATAL => qw(all);
use strict;
use Data::Dump qw(dump);
use Term::ANSIColor;
use Carp;
use JSON;
use POSIX qw(strftime);                                                         # http://www.cplusplus.com/reference/ctime/strftime/

=pod

=head1 Start Spot Instance From Latest AMI

=head2 Synopsis

Starts a cheap spot instance on Amazon Web Services (AWS) from your latest
Amazon Machine Image (AMI) snap shot more conveniently than using the AWS EC2
console to repetitively perform this task.

Offers the user a list of machine types of interest and their latest spot
prices on which to run the latest AMI.

=head2 Installation

Download this single standalone script to any convenient folder.

=head3 Perl

Perl can be obtained at:

L<http://www.perl.org>

You might need to install the following perl modules:

 cpan install Data::Dump Term::ANSIColor Carp JSON POSIX

=head3 AWS Command Line Interface

Prior to using this script you should:

Download/install the AWS CLI from:

L<http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html>

=head2 Configuration

=head3 AWS

Run:

 aws configure

to set up the AWS CLI used by this script.  The last question asked by aws
configure:

 Default output format [json]:

must be answered json.

You can confirm that aws cli is correctly installed by executing:

 aws ec2 describe-availability-zones

which should produce something like:

 {   "AvailabilityZones": [
         {   "ZoneName": "us-east-1a",
             "RegionName": "us-east-1",
             "Messages": [],
             "State": "available"
         },
     ]
 }

=head4 IAM users

If you are configuring an IAM userid please make sure that this userid is permitted
to execute the following commands:

 aws ec2 describe-images
 aws ec2 describe-key-pairs
 aws ec2 describe-security-groups
 aws ec2 describe-spot-price-history
 aws ec2 request-spot-instances

as these commands are used by the script to retrieve information required to
start the spot instance.

=head3 Perl

To configure this Perl script you should use the AWS EC2 console at:

L<https://console.aws.amazon.com/ec2/v2/home?region=us-east-1#Instances:sort=tag:Name>

to start and snap shot an instance, in the process creating the security group
and key pair whose details should be recorded below in this script in the
section marked B<user configuration>. Snap shot the running instance to create
an Amazon Machine Image (AMI) which can then be restarted quickly and
conveniently using this script. The script automatically finds the latest
snapshot each time it is run so there is no need to update this script to
account for each new snapshot made.

Configure this script by filling in the values in the B<user configuration>
area below.

=head2 Operation

Run:

 perl startSpotInstanceFromLatestAMI.pl

For example:

 Image         : ami-f0a6bd98 created at 2015-05-22T08:11:43.000Z - Ubuntu 2015-05-22
 Key pair      : AmazonKeyPair
 Security group: sg-915543f9 - open access
 Number  Type                    Price   Zone
 001     t1.micro                0.0037  us-east-1c
 002     m1.small                0.0073  us-east-1b
 003     m1.medium               0.0088  us-east-1c
 004     m3.medium               0.0143  us-east-1e
 005     m1.large                0.0166  us-east-1b
 006     m3.large                0.0195  us-east-1c
 007     m1.xlarge               0.0330  us-east-1b
 008     m3.xlarge               0.0394  us-east-1c
 009     m2.xlarge               0.0481  us-east-1b
 010     m2.2xlarge              0.0651  us-east-1a
 011     m2.4xlarge              0.0914  us-east-1c
 012     m3.2xlarge              0.1372  us-east-1c
 Enter number of instance type to request (above) or just hit enter to abort:
 1
 Your Spot request has been submitted for review, and is pending evaluation.

to choose and start a t1.micro spot instance.

Unwanted spot instances should be cancelled promptly at:

L<https://console.aws.amazon.com/ec2sp/v1/spot/home>

to avoid charges from AWS - otherwise once the spot request has been fulfilled
by an instance you will be charged at the current hourly spot price until you
terminate the instance.

Please note that AWS can repossess the spot instance at any time, thus all
permanent data used by the spot instance should be held in AWS S3 and updated
frequently by calling the S3 backup command:

 aws s3 sync

New software configurations should be backed up by creating a new AMI - this
script will automatically start the latest such AMI created.

=head2 Bugs

Please reports bugs as issues on this project at GitHub:

L<https://github.com/philiprbrenan/StartSpotInstanceFromLatestAMI>

and attach a copy of the indicated log file if appropriate.

=cut

# Start user configuration
my $keyPair            = qr(AmazonKeyPair);                                     # Choose the keypair via a regular expression which matches the key pair name
my $security           = qr(open);                                              # Choose the security group via a regular expression which matches the description or the name of the security group
my $instanceTypes      = qr(\A[mt]\d\.);                                        # Choose the instance types to consider via a regular expression. The latest spot instance prices will be rerueved and presented to the user allowing a manual selection on price to be made
my $productDescription = "Linux/UNIX";                                          # General type of OS to be run on the instance - Windows is 4x Linux in price.
my $bidPriceMultiplier = 1.25;                                                  # Multiply the spot price by this value to get the bid price for the spot instance

my $testing              = 0;                                                   # 0 - for real, not testing, 1 - Use previous test results rather than executing commands
my $useTestPrice         = 0;                                                   # 0 - use a bid price computed from the current spot price that is likely to work, 1 - use the following price for the requested spot request for testing purposes
my $testSpotRequestPrice = 0.001;                                               # A price (in US dollars) low enough to be rejected for any spot request yet still be accepted as syntactically correct
# End user configuration

sub timeStamp()     {strftime('%H:%M:%S', localtime)}

my $logFile = "zzz$0.data"; unlink $logFile;                                    # Log file

sub Log                                                                         # Append a message to the log file
 {my $t = join '', @_;
  my $f;
  open $f, ">>$logFile" or confess "Cannot open file $logFile";
  say {$f} &timeStamp, ' ', $t;
 }

sub wc(@)                                                                       # Colour a message
 {my $c = shift;
  my $t = join '', @_;
  $^O =~ /linux/i ? colored($t, $c) : $t;
 }

sub ws(@)                                                                       # Write a message possibly in colour and append it to the log file
 {my ($c, @t) = @_;
  Log(@t);
  say STDERR wc(@_);
 }

sub wn(@)                                                                       # Write a message normally
 {Log(@_);
  say STDERR @_;
 }

sub Yellow(@) {ws('yellow bold', @_)}                                           # Write stuff in yellow
sub Green (@) {ws('green  bold', @_)}                                           # Write stuff in green
sub Red   (@) {ws('red    bold', @_); confess @_, "\n"}                         # Write stuff in red and confess
sub yellow(@) {wc('yellow bold', @_)}                                           # Wrap stuff in yellow
sub green (@) {wc('green  bold', @_)}                                           # Wrap stuff in green
sub red   (@) {wc('red    bold', @_)}                                           # Wrap stuff in red

sub awsEc2($;$)                                                                 # Execute an Ec2 command and return the error code and Json converted to a Perl data structure
 {my ($c, $t) = @_;                                                             # Command, test data
  $c =~ s/\n/ /g; $c = "aws ec2 $c";                                            # Put command on one line

  my ($j, $r) = sub                                                             # Test or execute
   {return ($t, 0) if $testing;
    my $p = qx($c);
    my $r = $?;
    ($p, $r);
   }->();

  Log 'awsEc2 ', dump({r=>$r, j=>$j});
  my $p = decode_json($j);
  ($r, $p)
 }

sub describeImages                                                              # Images
 {awsEc2(<<END, &testDescribeImages)
describe-images --owners self
END
 }

sub describeKeyPairs                                                            # Keypairs
 {awsEc2(<<END, &testDescribeKeyPairs)
describe-key-pairs
END
 }

sub describeSecurityGroups                                                      # Security groups
 {awsEc2(<<END, &testDescribeSecurityGroups)
describe-security-groups
END
 }

sub describeSpotPriceHistory(@)
 {my @types = @_;                                                               # Instance types which match the re for which spot history is required
  my $types = join ' ', @types;
  my $time  = time(); my $timeStart = $time-3600;                               # Last hour of spot pricing history
 awsEc2(<<END, &testDescribeSpotPriceHistory)
describe-spot-price-history --instance-types $types --start-time $timeStart --end-time $time --product-description "$productDescription"
END
 }

sub latestImage                                                                 # Details of latest image
 {my ($r, $p) = describeImages;
  unless($r)
   {my @i;
    for(@{$p->{Images}})
     {my ($c, $d, $i) = @$_{qw(CreationDate Description ImageId)}; $d //= '';
      push @i, [$i, $c, $d];
     }
    Log 'latestImage ', dump(\@i);
    my @I = sort {$b->[1] cmp $a->[1]} @i;                                      # Images, with most recent first
    return $I[0];                                                               # Latest image name
   }
  Red "No images available, please logon to AWS and create one";
 }

sub checkedKeyPair                                                              # Key pair that matches the keyPair global
 {my ($r, $p) = describeKeyPairs;
  unless($r)
   {my @k;
    for(@{$p->{KeyPairs}})
     {my ($n, $f) = @$_{qw(KeyName KeyFingerprint)};
      push @k, $n if $n =~ m/$keyPair/i;
     }
    Log 'checkedKeyPair ', dump(@k);
    return $k[0] if @k == 1;                                                    # Found the matching key pair
    Red "No unique match for key pair $keyPair, please choose one from the list above and use it to set the keyPair global variable at the top of this script";
   }
  Red "No key pairs available, please logon to AWS and create one";
 }

sub checkedSecurityGroup                                                        # Choose the security group that matches the securityGroup global
 {my ($r, $p) = describeSecurityGroups;
  unless($r)
   {my @g;
    for(@{$p->{SecurityGroups}})
     {my ($d, $g) = @$_{qw(Description GroupId)}; $d //= '' ;                   # Ensure description is not null
      push @g, [$g, $d]  if $d =~ m/$security/i or $g =~ m/$security/i;
     }
    Log 'checkedSecurityGroup ', dump(\@g);
    return $g[0] if @g == 1;                                                    # Found the matching key pair
    Red "No unique match for key pair $security, please choose one from the list above and use it to set the security global variable at the top of this script";
   }
  Red "No security groups available, please logon to AWS and create one";
 }

sub checkedInstanceTypes                                                        # Choose the instance types of interest
 {my @I = &instanceTypes;
  my @i = grep {/$instanceTypes/i} @I;
  Log 'checkedInstanceTypes ', dump(\@i);
  return @i if @i;                                                              # Found the matching key pair
  Red "Please choose from: ". join(' ', @I). " using the instanceType global at the top of this script";
 }

sub spotPriceHistory(@)                                                         # Get spot prices for instances of interest
 {my @instanceTypes = @_;
  my ($r, $p) = describeSpotPriceHistory(@instanceTypes);
  unless($r)
   {my %p;
    for(@{$p->{SpotPriceHistory}})
     {my ($t, $z, $p) = @$_{qw(InstanceType AvailabilityZone SpotPrice)};
      push @{$p{$t}{$z}}, $p;
     }
    Log 'spotPriceHistory 1111 ', dump(\%p);
    for   my $t(keys %p)                                                        # Average price for each zone
     {for my $z(keys %{$p{$t}})
       {my @p = @{$p{$t}{$z}};
        my $a = 0; $a += $_ for @p; $a /= @p; $a = int(1e4*$a)/1e4;             # Round average price
        $p{$t}{$z} = $a;
       }
     }
    Log 'spotPriceHistory 2222 ', dump(\%p);
    for   my $t(keys %p)                                                        # Cheapest zone for each type
     {my $Z;
      for my $z(keys %{$p{$t}})
       {$Z = $z if !$Z or $p{$t}{$z} < $p{$t}{$Z};
       }
      $p{$t} = [$t, $Z, $p{$t}{$Z}];
     }
    Log 'spotPriceHistory 3333 ', dump(\%p);
    return map {$p{$_}} sort {$p{$a}[2] <=> $p{$b}[2]} keys %p;                 # Cheapest zone and price for each type in price order
   }
  Red "No spot history available";
 }

sub requestSpotInstance
 {my $latestImage = &latestImage;
  my ($imageId, $imageDescription, $imageDate) = @$latestImage;
  wn "Image         : ", green($imageId), " created at $imageDate - $imageDescription";

  my $keyPair = &checkedKeyPair;
  wn "Key pair      : ", green($keyPair);

  my $securityGroup = &checkedSecurityGroup;
  my ($securityGroupName, $securityGroupDesc) = @$securityGroup;
  wn "Security group: ", green($securityGroupName), " - $securityGroupDesc";

  my @instanceTypes = checkedInstanceTypes;
  my @spotPriceHistory = spotPriceHistory(@instanceTypes);                      # Get spot prices for instances of interest

  Green("Number  Type                    Price   Zone");
  for(1..@spotPriceHistory)
   {my ($spotType, $spotZone, $spotPrice) = @{$spotPriceHistory[$_-1]};
    wn sprintf("%03s     %-20.20s  %8.4f  %.16s", $_,  $spotType,  $spotPrice, $spotZone);
   }
  Yellow("Enter number of instance type to request (above) or just hit enter to abort:");

  my $r = $testing ? "1\n" :  <>; $r //= ''; chomp($r);
  unless($r =~ /\A\d+\Z/ and $r > 0 and $r <= @spotPriceHistory)
   {wn red "No spot instance requested";
    return
   }
  my ($spotType, $spotZone, $spotPrice) = @{$spotPriceHistory[substr($r, 0, 1)-1]};

  my $spec = <<END;                                                             # Instance specification
 {"ImageId": "$imageId",
  "KeyName": "$keyPair",
  "SecurityGroupIds": ["$securityGroupName"],
  "InstanceType": "$spotType",
  "Placement": {"AvailabilityZone": "$spotZone"}
 }
END

  my $bidPrice = $useTestPrice ? $testSpotRequestPrice : $bidPriceMultiplier * $spotPrice; # Bid price

  my $cmd = <<END;                                                              # Command to request spot instance
request-spot-instances --spot-price $bidPrice --type "one-time" --launch-specification '$spec'
END

  if (1)                                                                        # Execute command requesting spot instance
   {my ($r, $p) = awsEc2($cmd, &testRequestSpotInstance);
    unless ($r)
     {my $message = $p->{SpotInstanceRequests}[0]{Status}{Message};
      Yellow($message);
      return;
     }
    Red "Error requesting spot instance, please go to: https://console.aws.amazon.com/ec2sp/v1/spot/home";
   }
  Red "Spot instance not requested";
 }

sub checkVersion
 {my @w = split /\s+/, qx(aws --version);
  my @v = $w[0] =~ m/(\d+)/g;
  return 1 if $v[0] >   1;
  return 1 if $v[1] >= 10;
  Red "Version  of aws cli too low - please reinstall from: http://docs.aws.amazon.com/cli/latest/userguide/installing.html";
 }

# Run

checkVersion;                                                                   # Check version

eval {requestSpotInstance};                                                     # Request an instance

if ($@)
 {Red "Please send me file:\n$logFile\n";
 }
else {unlink $logFile}                                                          # Not needed  if we got here

#-------------------------------------------------------------------------------
# Test data
#-------------------------------------------------------------------------------
#pod2markdown < startSpotInstanceFromLatestAMI.pl > README.md

sub instanceTypes{split /\n/, <<END}
t1.micro
t2.nano
t2.micro
t2.small
t2.medium
t2.large
m1.small
m1.medium
m1.large
m1.xlarge
m3.medium
m3.large
m3.xlarge
m3.2xlarge
m4.large
m4.xlarge
m4.2xlarge
m4.4xlarge
m4.10xlarge
m4.16xlarge
m2.xlarge
m2.2xlarge
m2.4xlarge
cr1.8xlarge
r3.large
r3.xlarge
r3.2xlarge
r3.4xlarge
r3.8xlarge
x1.16xlarge
x1.32xlarge
i2.xlarge
i2.2xlarge
i2.4xlarge
i2.8xlarge
hi1.4xlarge
hs1.8xlarge
c1.medium
c1.xlarge
c3.large
c3.xlarge
c3.2xlarge
c3.4xlarge
c3.8xlarge
c4.large
c4.xlarge
c4.2xlarge
c4.4xlarge
c4.8xlarge
cc1.4xlarge
cc2.8xlarge
g2.2xlarge
g2.8xlarge
cg1.4xlarge
p2.xlarge
p2.8xlarge
p2.16xlarge
d2.xlarge
d2.2xlarge
d2.4xlarge
d2.8xlarge
END

sub testRequestSpotInstance{<<END}
{
    "SpotInstanceRequests": [
        {
            "Type": "one-time",
            "Status": {
                "UpdateTime": "2016-11-14T19:20:12.000Z",
                "Message": "Your Spot request has been submitted for review, and is pending evaluation.",
                "Code": "pending-evaluation"
            },
            "SpotPrice": "0.002000",
            "ProductDescription": "Linux/UNIX",
            "LaunchSpecification": {
                "Monitoring": {
                    "Enabled": false
                },
                "InstanceType": "t1.micro",
                "ImageId": "ami-f0a6bd98",
                "Placement": {
                    "AvailabilityZone": "us-east-1b"
                },
                "SecurityGroups": [
                    {
                        "GroupId": "sg-915543f9",
                        "GroupName": "open"
                    }
                ],
                "KeyName": "AmazonKeyPair"
            },
            "CreateTime": "2016-11-14T19:20:12.000Z",
            "SpotInstanceRequestId": "sir-6rgg45ij",
            "State": "open"
        }
    ]
}
END

sub testDescribeSpotPriceHistory {<<END}
{
    "SpotPriceHistory": [
        {
            "InstanceType": "m1.xlarge",
            "AvailabilityZone": "us-east-1b",
            "SpotPrice": "0.033200",
            "Timestamp": "2016-11-12T19:22:24.000Z",
            "ProductDescription": "Linux/UNIX"
        },
        {
            "InstanceType": "m1.xlarge",
            "AvailabilityZone": "us-east-1b",
            "SpotPrice": "0.033100",
            "Timestamp": "2016-11-12T19:15:57.000Z",
            "ProductDescription": "Linux/UNIX"
        },
        {
            "InstanceType": "m1.xlarge",
            "AvailabilityZone": "us-east-1b",
            "SpotPrice": "0.033000",
            "Timestamp": "2016-11-12T19:12:16.000Z",
            "ProductDescription": "Linux/UNIX"
        }
    ]
}
END

sub testDescribeKeyPairs {<<END}                                                # Test key pairs
 {
    "KeyPairs": [
        {
            "KeyName": "AmazonKeyPair",
            "KeyFingerprint": "b5:b6:f2:06:f3:13:76:5d:37:46:72:cf:2a:6b:cd:f2:0f:71:6a:2c"
        }
    ]
}
END

sub testDescribeImages {<<END}                                                  # Test describe images
 {   "Images": [
        {
            "Public": false,
            "Description": "Ubuntu 2015-05-22",
            "Hypervisor": "xen",
            "KernelId": "aki-919dcaf8",
            "Tags": [
                {
                    "Value": "Ubuntu 2015-05-22",
                    "Key": "Name"
                }
            ],
            "Architecture": "x86_64",
            "OwnerId": "123456789012",
            "ImageLocation": "123456789012/Ubuntu 2015-05-22",
            "Name": "Ubuntu 2015-05-22",
            "ImageType": "machine",
            "RootDeviceName": "/dev/sda1",
            "BlockDeviceMappings": [
                {
                    "DeviceName": "/dev/sda1",
                    "Ebs": {
                        "SnapshotId": "snap-1cde1d53",
                        "DeleteOnTermination": true,
                        "Encrypted": false,
                        "VolumeSize": 8,
                        "VolumeType": "standard"
                    }
                }
            ],
            "CreationDate": "2015-05-22T08:11:43.000Z",
            "VirtualizationType": "paravirtual",
            "State": "available",
            "ImageId": "ami-f0a6bd98",
            "RootDeviceType": "ebs"
        },
        {
            "Public": false,
            "Description": "Ubuntu 2015-05-21",
            "Hypervisor": "xen",
            "KernelId": "aki-919dcaf8",
            "Tags": [
                {
                    "Value": "Ubuntu 2015-05-21",
                    "Key": "Name"
                }
            ],
            "Architecture": "x86_64",
            "OwnerId": "123456789012",
            "ImageLocation": "123456789012/Ubuntu 2015-05-21",
            "Name": "Ubuntu 2015-05-21",
            "ImageType": "machine",
            "RootDeviceName": "/dev/sda1",
            "BlockDeviceMappings": [
                {
                    "DeviceName": "/dev/sda1",
                    "Ebs": {
                        "SnapshotId": "snap-1cde1d53",
                        "DeleteOnTermination": true,
                        "Encrypted": false,
                        "VolumeSize": 8,
                        "VolumeType": "standard"
                    }
                }
            ],
            "CreationDate": "2015-05-21T08:11:43.000Z",
            "VirtualizationType": "paravirtual",
            "State": "available",
            "ImageId": "ami-f0a6bd97",
            "RootDeviceType": "ebs"
        }
    ]
}
END

sub testDescribeSecurityGroups {<<END}                                          # Test describe SecurityGroups
{
    "SecurityGroups": [
        {
            "Description": "AWS OpsWorks blank server - do not change or delete",
            "IpPermissions": [
                {
                    "PrefixListIds": [],
                    "IpProtocol": "tcp",
                    "UserIdGroupPairs": [],
                    "IpRanges": [
                        {
                            "CidrIp": "0.0.0.0/0"
                        }
                    ],
                    "FromPort": 22,
                    "ToPort": 22
                }
            ],
            "IpPermissionsEgress": [],
            "GroupId": "sg-67d7cb0f",
            "OwnerId": "123456789012",
            "GroupName": "AWS-OpsWorks-Blank-Server"
        },
        {
            "Description": "open access",
            "IpPermissions": [
                {
                    "PrefixListIds": [],
                    "IpProtocol": "tcp",
                    "UserIdGroupPairs": [],
                    "IpRanges": [
                        {
                            "CidrIp": "0.0.0.0/0"
                        }
                    ],
                    "FromPort": 0,
                    "ToPort": 65535
                },
                {
                    "PrefixListIds": [],
                    "IpProtocol": "udp",
                    "UserIdGroupPairs": [],
                    "IpRanges": [
                        {
                            "CidrIp": "0.0.0.0/0"
                        }
                    ],
                    "FromPort": 0,
                    "ToPort": 65535
                },
                {
                    "PrefixListIds": [],
                    "IpProtocol": "icmp",
                    "UserIdGroupPairs": [],
                    "IpRanges": [
                        {
                            "CidrIp": "0.0.0.0/0"
                        }
                    ],
                    "FromPort": -1,
                    "ToPort": -1
                }
            ],
            "IpPermissionsEgress": [],
            "GroupId": "sg-915543f9",
            "Tags": [
                {
                    "Key": "Name",
                    "Value": "Open"
                }
            ],
            "OwnerId": "123456789012",
            "GroupName": "open"
        }
    ]
}
END

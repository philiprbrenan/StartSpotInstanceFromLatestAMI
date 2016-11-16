# Start Spot Instance From Latest AMI

## Synopsis

Starts a cheap spot instance on Amazon Web Services (AWS) from your latest
Amazon Machine Image (AMI) snap shot more conveniently than using the AWS EC2
console to repetitively perform this task.

Offers a list of machine types of interest and their latest spot prices on
which to run the latest AMI.

## Installation

Download this single standalone Perl script to any convenient folder.

### Perl

Perl can be obtained at:

[http://www.perl.org](http://www.perl.org)

You might need to install the following perl modules:

    cpan install Data::Dump Term::ANSIColor Carp JSON POSIX

### AWS Command Line Interface

Prior to using this script you should download/install the AWS CLI from:

[http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html)

## Configuration

### AWS

Run:

    aws configure

to set up the AWS CLI used by this script.  The last question asked by aws
configure:

    Default output format [json]:

must be answered **json**.

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

#### IAM users

If you are configuring an IAM userid please make sure that this userid is permitted
to execute the following commands:

    aws ec2 describe-images
    aws ec2 describe-key-pairs
    aws ec2 describe-security-groups
    aws ec2 describe-spot-price-history
    aws ec2 request-spot-instances

as these commands are used by the script to retrieve information required to
start the spot instance.

### Perl

To configure this Perl script you should use the AWS EC2 console at:

[https://console.aws.amazon.com/ec2/v2/home](https://console.aws.amazon.com/ec2/v2/home)

to start and snap shot an instance, in the process creating the security group
and key pair whose details should be recorded below in this script in the
section marked **user configuration**. Snap shot the running instance to create
an Amazon Machine Image (AMI) which can then be restarted quickly and
conveniently using this script. The script automatically finds the latest
snapshot each time it is run so there is no need to update this script to
account for each new snapshot made.

Configure this script by filling in the values in the **user configuration**
area below.

## Operation

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

[https://console.aws.amazon.com/ec2sp/v1/spot/home](https://console.aws.amazon.com/ec2sp/v1/spot/home)

to avoid charges from AWS - otherwise once the spot request has been fulfilled
by an instance you will be charged at the current hourly spot price until you
terminate the instance.

Please note that AWS can repossess the spot instance at any time, thus all
permanent data used by the spot instance should be held in AWS S3 and updated
frequently by calling the S3 backup command:

    aws s3 sync

New software configurations should be backed up by creating a new AMI - this
script will automatically start the latest such AMI created.

## Bugs

Please reports bugs as issues on this project at GitHub:

[https://github.com/philiprbrenan/StartSpotInstanceFromLatestAMI](https://github.com/philiprbrenan/StartSpotInstanceFromLatestAMI)

and attach a copy of the indicated log file if appropriate.

## Licence

Perl Artistic License 2.0

[http://www.perlfoundation.org/artistic\_license\_2\_0/](http://www.perlfoundation.org/artistic_license_2_0/)

This module is free software. It may be used, redistributed and/or modified
under the same terms as Perl itself.

#
# Copyright (c) 2008 - 2012 Novell, Inc.
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail,
# you may find current contact information at www.novell.com
#

#
# YSR.pm - interface for YaST to interact with SUSE::SuseRegister
#
# Authors: Michael Calmer <mc@suse.de>
#          J. Daniel Schmidt <jdsn@suse.de>
#

package YSR;

use strict;
use SUSE::SuseRegister;
use Data::Dumper;
use XML::Simple;

use YaPI;

our %TYPEINFO;

my $global_ctx = {};

# flag files for registration status
my $FFwebyast_dir = '/var/lib/yastws';
my $FFwebyast     = $FFwebyast_dir.'/registration_successful';
my $FFgeneric_dir = '/var/lib/suseRegister';
my $FFgeneric     = $FFgeneric_dir.'/y2_registration_successful';

# set the PATH in the perl environment (bnc#621914)
# otherwise it is empty in system calls
$ENV{PATH}="/usr/bin:/sbin:/usr/sbin:/bin";

BEGIN { $TYPEINFO{init_ctx} = ["function", "void", [ "map", "string", "any"]]; }
sub init_ctx
{
    my $self = shift;
    my $data = shift;

    if(defined $global_ctx && ref($global_ctx) eq "HASH" && exists $global_ctx->{debug})
    {
        # ctx is initialized; clean it before we re-init it
        $self->del_ctx();
    }

    $global_ctx = SUSE::SuseRegister::init_ctx($data);
}

BEGIN { $TYPEINFO{del_ctx} = ["function", "void"]; }
sub del_ctx
{
    my $self = shift;

    if(defined $global_ctx && ref($global_ctx) eq "HASH" && exists $global_ctx->{debug})
    {
        # only call del_ctx if it is initialized
        SUSE::SuseRegister::del_ctx($global_ctx);
    }

    $global_ctx = {};
}

BEGIN { $TYPEINFO{get_errorcode} = [ "function", "integer"]; }
sub get_errorcode
{
   my $self = shift;

   return $global_ctx->{errorcode};
}

BEGIN { $TYPEINFO{get_errormsg} = [ "function", "string"]; }
sub get_errormsg
{
   my $self = shift;

   return $global_ctx->{errormsg};
}

BEGIN { $TYPEINFO{listParams} = ["function", "string"]; }
sub listParams
{
    my $self = shift;

    return SUSE::SuseRegister::listParams($global_ctx);
}

BEGIN { $TYPEINFO{register} = ["function", "integer"]; }
sub register
{
    my $self = shift;

    my $ret = SUSE::SuseRegister::register($global_ctx);

    return $ret;
}

BEGIN { $TYPEINFO{getTaskList} = ["function", [ "map", "string", "any"] ]; }
sub getTaskList
{
    my $self = shift;

    return SUSE::SuseRegister::getTaskList($global_ctx);
}

BEGIN { $TYPEINFO{get_args} = [ "function", [ "map", "string", ["map", "string", "string"]]]; }
sub get_args
{
   my $self = shift;

   return $global_ctx->{args};
}

BEGIN { $TYPEINFO{set_args} = [ "function", "void", [ "map", "string", ["map", "string", "string"]]]; }
sub set_args
{
   my $self = shift;
   my $args = shift;

   if(defined $args && ref($args) eq "HASH")
   {
       $global_ctx->{args} = $args;
   }
}

BEGIN { $TYPEINFO{set_arg} = [ "function", "void", "string", [ "map", "string", "string"]]; }
sub set_arg
{
   my $self  = shift;
   my $key   = shift;
   my $value = shift;

   if(defined $key && $key ne "")
   {
       if(defined $value && ref($value) eq "HASH" )
       {
           $global_ctx->{args}->{$key} = $value;
       }
       else
       {
           delete $global_ctx->{args}->{$key};
       }
   }
}

BEGIN { $TYPEINFO{get_manualURL} = [ "function", "string"]; }
sub get_manualURL
{
   my $self = shift;

   return $global_ctx->{registerManuallyURL};
}

BEGIN { $TYPEINFO{get_registerReadableText} = [ "function", "string"]; }
sub get_registerReadableText
{
   my $self = shift;

   return join('', @{$global_ctx->{registerReadableText}});
}

BEGIN { $TYPEINFO{get_registerPrivPol} = [ "function", "string"]; }
sub get_registerPrivPol
{
   my $self = shift;

   return $global_ctx->{registerPrivPol};
}

BEGIN { $TYPEINFO{saveLastZmdConfig} = [ "function", ["list", "any"]]; }
sub saveLastZmdConfig
{
   my $self = shift;

   return SUSE::SuseRegister::saveLastZmdConfig($global_ctx);
}

BEGIN { $TYPEINFO{set_proxy} = ["function", "void", "string", "string"]; }
sub set_proxy
{
    my $self = shift;
    my $http_proxy = shift;
    my $https_proxy = shift;

    if(defined $http_proxy && $http_proxy =~ /^http/)
    {
        $ENV{http_proxy} = $http_proxy;
    }

    if(defined $https_proxy && $https_proxy =~ /^http/)
    {
        $ENV{https_proxy} = $https_proxy;
    }
}

BEGIN { $TYPEINFO{unset_proxy} = ["function", "void"]; }
sub unset_proxy
{
    my $self = shift;
    delete $ENV{http_proxy}; 
    delete $ENV{https_proxy}; 
}

BEGIN { $TYPEINFO{statelessregister} = ["function", [ "map", "string", "any"], ["map", "string", "any"], ["map", "string", "any"]]; }
sub statelessregister
{
    my $self  = shift;
    my $ctx = shift;
    my $arguments = shift;

    unless ( defined $ctx && ref($ctx) eq "HASH" )
    {
        return { 'error'        => 'The context is missing or invalid.',
                 'contexterror' => '1' };
    }

    # always do a fresh init of proxy and context - otherwise old cached wrong data may be used
    # 1. proxy - fixed proxy settings (bnc#626965)
    $self->unset_proxy();
    if ( exists $ctx->{'proxy-http_proxy'} || exists $ctx->{'proxy-https_proxy'} )
    {
        my $http_proxy  = $ctx->{'proxy-http_proxy'}  || undef;
        my $https_proxy = $ctx->{'proxy-https_proxy'} || undef;
        $self->set_proxy($http_proxy, $https_proxy);
        delete $ctx->{'proxy-http_proxy'};
        delete $ctx->{'proxy-https_proxy'};
    }

    # 2. registration context
    $self->init_ctx($ctx);
    my $init_err = $self->get_errorcode();

    unless ($init_err == 0)
    {
        # init failed
        return {  'error'     => 'The initialization of the registration failed.'
                 ,'initerror' => $init_err
                 ,'errorcode' => 199
               };
        }

    # set arguments
    # must be set one for one, otherwise other data would be overwritten
    foreach my $key ( keys %{$arguments} )
    {
        ## $self->set_arg( $key, { flag => 'i', value => ${$arguments}{$key} , kind => 'mandatory' } );
        ## $self->set_arg( $key, { value => ${$arguments}{$key} } );
        $self->set_arg( $key, { 'value' => ${$arguments}{$key} } );
    }

    # run registration
    my $exitcode = 1;
    my $errorcode = 0;
    my $readabletext = '';
    my $tasklist = '';
    my $manualurl = '';
    my @log = [];

    my $counter = 0;
    do
    {
        $exitcode = $self->register();
        $counter++;
    } while ( $exitcode == 1  &&  $counter < 5 );

    $errorcode = $self->get_errorcode();
    $readabletext = $self->get_registerReadableText();
    $manualurl = $self->get_manualURL();


    my $regret = {  'exitcode'     => $exitcode
                   ,'errorcode'    => $errorcode
                   ,'readabletext' => $readabletext
                   ,'manualurl'    => $manualurl
                 };

    # we had a new registration process - so we reset the flag files
    $self->removeregisteredflag();

    if ( $exitcode == 0 )
    {
        # successful registration, so we need to save the last ZMD config
        $self->saveLastZmdConfig();
        $tasklist = $self->getTaskList() || {};
        my $ret = $self->changerepos($tasklist);

        if ( ref($ret) eq 'HASH' )
        {
            my $rlog = ${$ret}{'log'} || [];
            ${$regret}{'repochangeslog'} = XMLout( { 'log' => $rlog}, rootname => 'log' );

            my $errcount = 0;
            foreach my $logline ( @{$rlog} )
            {
                $errcount++ if $logline =~ /^ERROR:/;
            }
            ${$regret}{'repochangeerrors'} = $errcount if $errcount > 0;
        }

        ${$regret}{'success'}  = 'Successfully ran registration';
        # prepare the tasklist for XML conversion
        foreach my $k (keys %{$tasklist})
        {
            if ( exists ${${$tasklist}{$k}}{'CATALOGS'} )
            {
                ${${$tasklist}{$k}}{'CATALOGS'} = { 'catalog' => ${${$tasklist}{$k}}{'CATALOGS'} };
            }
        }
        ${$regret}{'tasklist'} =  XMLout( {'item' => $tasklist}, rootname => 'tasklist', KeyAttr => { item => "+ALIAS", catalog => "+ALIAS" }, NoAttr => 1);

        # write flagfile for successful registration
        $self->setregisteredflag(1);

        # to be on the safe side for a following registration request, we need to delete the context data
        $self->del_ctx();
    }
    elsif ( $exitcode == 2 ) # catch error 2 and send error message up one layer (bnc#604777)
    {
        ${$regret}{'error'} = 'Registration did not succeed due to invalid data.';
        ${$regret}{'invaliddataerror'} = '1';
        ${$regret}{'invaliddataerrormessage'} = $self->get_errormsg();
        # to be on the safe side for a following registration request, we need to delete the context data
        $self->del_ctx();
    }
    elsif ( $exitcode == 3 )
    {
        ${$regret}{'error'} = 'Conflicting registration data';
        ${$regret}{'conflicterror'} = '1';
        # to be on the safe side for a following registration request, we need to delete the context data
        $self->del_ctx();
    }
    elsif ( $exitcode == 4 )
    {
        ${$regret}{'missinginfo'} = 'Missing Information';
        my $margs = $self->get_args() || {};
        ${$regret}{'missingarguments'} = XMLout($margs, rootname => 'missingarguments');
        # keep the context, do not delete it
    }
    elsif ( $exitcode == 100 || $exitcode == 101 )
    {
        ${$regret}{'error'} = 'No products to register';
        ${$regret}{'noproducterror'} = '1';
        # to be on the safe side for a following registration request, we need to delete the context data
        $self->del_ctx();
    }
    else
    {
        ${$regret}{'error'} = 'Registration was not successful';
        # to be on the safe side for a following registration request, we need to delete the context data
        $self->del_ctx();
    }

    return $regret;
}


BEGIN { $TYPEINFO{getregistrationconfig} = ["function", [ "map", "string", "any"] ]; }
sub getregistrationconfig
{
    my $self = shift;
    my $SRconf = '/etc/suseRegister.conf';
    my $SRcert = '/etc/ssl/certs/registration-server.pem';
    my $SRcredentials = '/etc/zypp/credentials.d/NCCcredentials';

    my $url = undef;
    my $cert = undef;
    my $guid = undef;

    # read the registration server url
    if ( -e $SRconf )
    {
        if (open(CNF, "< $SRconf") )
        {
            while(<CNF>)
            {
                next if($_ =~ /^\s*#/);

                if($_ =~ /^url\s*=\s*(\S*)\s*/ && defined $1 && $1 ne '')
                {  $url = $1;  }
            }
            close CNF;
        }
    }

    #read the registration server ca certificate file
    if ( -e $SRcert )
    {
        my $separator = $/;
        local $/ = undef;
        if ( open(CERT, "< $SRcert") )
        {
            $cert = <CERT>;
            close CERT;
        }
        $/ = $separator;
    }

    # read the guid
    if ( -e $SRcredentials  &&  $self->getregisteredflag() )
    {
        if (open(CRED, "< $SRcredentials") )
        {
            while(<CRED>)
            {
                next if($_ =~ /^\s*#/);

                if($_ =~ /^\s*username\s*=\s*(\S*)\s*/ && defined $1 && $1 ne '')
                {  $guid = $1;  }
            }
            close CRED;
        }
    }

    $url  = '' unless defined $url;
    $cert = '' unless defined $cert;
    $guid = '' unless defined $guid;

    # delete a flagfile that might be still there if no guid is found
    $self->removeregisteredflag() if $guid eq '';

    return { "regserverurl" => $url,
             "regserverca"  => $cert,
             "guid"         => $guid };
}


BEGIN { $TYPEINFO{setregistrationconfig} = ["function", "integer", [ "map", "string", "string"] ]; }
sub setregistrationconfig
{
    my $self = shift;
    my $config = shift;

    my $SRconf     = '/etc/suseRegister.conf';
    my $SRcertpath = '/etc/ssl/certs/';
    my $SRcert     = "$SRcertpath/registration-server.pem";
    my $SRcertnew  = "$SRcertpath/registration-server.pem_new";

    my $url  = ${$config}{'regserverurl'} || undef;
    my $cert = ${$config}{'regserverca'}  || undef;
    my $newconfig = '';
    my $success = 0;

    # write the new registration server url to the suseRegister.conf file
    if ($url && $url =~ /^https:\/\//)
    {
        if ( -e $SRconf )
        {
            if (open(CNFR, "< $SRconf") )
            {
                while(<CNFR>)
                {
                    $_ =~ s/^url\s*=\s*(\S*)\s*/url = $url\n/;
                    $newconfig .= $_;
                }
                close CNFR;

                if ( open(CNFW, "> $SRconf") )
                {
                     print CNFW $newconfig;
                     close CNFW;
                     $success += 1;
                }
            }
        }
    }

    # write the new certificate and rehash the directory
    if ($cert)
    {
        if ( open(CERT, "> $SRcertnew") )
        {
            print CERT $cert;
            close CERT;
            # writing the file succeeded
            $success += 2;

            my @verifyargs = ('openssl', 'x509', '-in', "$SRcertnew", '-text');
            if ( system( @verifyargs ) == 0 )
            {
                my @moveargs = ('mv', "$SRcertnew", "$SRcert" );
                if ( system( @moveargs ) == 0 )
                {
                    # certificate validation succeeded and it was moved to the real file name
                    $success += 4;

                    # rehash the certificate pool
                    my @rehashargs = ('c_rehash', '/etc/ssl/certs/');
                    if ( system( @rehashargs ) == 0 )
                    {
                        # c_rehashing of certificate pool succeeded
                        $success += 8;
                    }
                }
            }
            else
            {
                # delete the *_new file
                unlink( $SRcertnew );
                # correct the success status
                $success -= 2;
            }
        }
    }

    return $success;
}


#
# setregisteredflag
#
# Write flagfile to identify a successful registration
# Note: this is only a good guess, only the registration server knows about the status
# (bnc#634026)
#
sub setregisteredflag()
{
    my $self = shift;
    my $status = shift;
    my $written = 0;

    my $status_str = time();
    $status_str = '' unless defined $status;


    # write flagfile for successful registration
    if ( -d $FFgeneric_dir )
    {
        if ( ! -e $FFgeneric || defined $status )
        {
            open( FFG, "> $FFgeneric" );
            print FFG "$status_str";
            close FFG;
        }
        $written = 1;
    }

    # this is the old location - will be obsoleted in follwing releases
    if ( -d $FFwebyast_dir )
    {
        if ( ! -e $FFwebyast || defined $status )
        {
            open( FFW, "> $FFwebyast" );
            print FFW "$status_str";
            close FFW;
        }
        $written = 1;
    }

    return $written;
}

#
# remove both registration flag files
#
# Remove flagfiles that identify a successful registration
# Note: this is only a good guess, only the registration server knows about the status
# (bnc#634026)
#
sub removeregisteredflag()
{
    my $self = shift;
    unlink($FFgeneric);
    unlink($FFwebyast);
}

#
# getregisteredflag status
#
#
# Get flagfile status to identify a successful registration
# Note: this is only a good guess, only the registration server knows about the status
# (bnc#634026)
#
sub getregisteredflag()
{
    my $self = shift;

    if ( -e $FFgeneric  ||  -e $FFwebyast )
    {
        # write them if only one is found
        $self->setregisteredflag(undef);
        return 1;
    }
    return 0;
}


#
# check catalogs
#
# check catalogs of services and apply changes according to the CATALOGS-subhash of the getTaskList hash
#
sub checkcatalogs
{
    my $self = shift;
    my $todo = shift;
    my $pService = shift;

    return ["Service name is undefined. Can not check the catalogs."] unless ( defined $pService );
    return ["Catalog list is empty. No catalogs to check."]           unless ( defined $todo  &&  ref($todo) eq 'HASH' );

    my @log = [];
    my ($catalog, $pAny);

    foreach $catalog (keys %{$todo})
    {
        $pAny = ${$todo}{$catalog};
        if ( not defined $catalog  ||  $catalog eq '' )
        {
            push @log, "A catalog returned by SuseRegister has no or an invalid name.";
        }
        elsif ( not defined $pAny  ||  ref($pAny) ne 'HASH' )
        {
            push @log, "A catalog returned by SuseRegister did not contain any details: $catalog";
        }
        else
        {
            if ( not exists ${$pAny}{'ALIAS'} || not defined ${$pAny}{'ALIAS'} || ${$pAny}{'ALIAS'} eq '' )
            {
                push @log, "A catalog returned by SuseRegister has no or an invalid alias name.";
            }
            else
            {
                if ( not exists ${$pAny}{'TASK'} || not defined ${$pAny}{'TASK'} || ${$pAny}{'TASK'} eq '' )
                {
                    push @log, "A catalog returned by SuseRegister has an invalid task: $catalog ($pService)";
                }
                elsif ( ${$pAny}{"TASK"} eq 'le' ||  ${$pAny}{"TASK"} eq 'ld')
                {
                    push @log, "According to SuseRegister a catalog does not need to be changed: $catalog ($pService)";
                }
                elsif ( ${$pAny}{"TASK"} eq 'a' )
                {
                    push @log, "According to SuseRegister a catalog has to be enabled: $catalog ($pService)";
                    my @zCMD = ('zypper', '--non-interactive', 'modifyrepo', '--enable', "${$pAny}{'ALIAS'}");
                    if ( system(@zCMD) == 0 )
                    {
                        push @log, "Enabled catalog: ${$pAny}{'ALIAS'} ($pService)";
                    }
                    else
                    {
                        push @log, "ERROR: Could not enable catalog: ${$pAny}{'ALIAS'} ($pService)";
                    }
                }
                elsif ( ${$pAny}{"TASK"} eq 'd' )
                {
                    push @log, "According to SuseRegister a service has to be disabled: $catalog ($pService)";
                    my @zCMD = ('zypper', '--non-interactive', 'modifyrepo', '--disable', ${$pAny}{'ALIAS'});
                    if ( system(@zCMD) == 0 )
                    {
                        push @log, "Disabled catalog: ${$pAny}{'ALIAS'} ($pService)";
                    }
                    else
                    {
                        push @log, "ERROR: Could not enable catalog: ${$pAny}{'ALIAS'} ($pService)";
                    }
                }
            }
        }
    }

    return @log;
}


#
# change repos according to todo-list
#
# takes the resulting hash of getTaskList
#
BEGIN { $TYPEINFO{changerepos} = ["function", [ "map", "string", "any"], [ "map", "string", "any"] ]; }
sub changerepos
{
    my $self = shift;
    my $todo = shift;
    my @log    = [];

    unless (defined $todo  &&  ref($todo) eq "HASH"  &&  keys %{$todo} > 0)
    {
        push @log, "No changes need to be done to the package system.";
        return { 'log' => @log };
    }

    my ($pService, $pAny);
    foreach $pService (keys %{$todo})
    {
        $pAny = ${$todo}{$pService};

        if ( ref($pAny) ne 'HASH' )
        {
            push @log, "A service returned by SuseRegister did not contain any details: $pService";
        }
        elsif ( not defined $pService  || $pService eq '')
        {
            push @log, "A service returned by SuseRegister has no or an invalid name.";
        }
        else
        {
            if ( defined ${$pAny}{'TYPE'} )
            {
                if ( ${$pAny}{'TYPE'} eq 'zypp' )
                {
                    push @log, "Handling a service of the type zypp";

                    if ( not defined ${$pAny}{'TASK'}  ||  ${$pAny}{'TASK'} eq '' )
                    {
                        push @log, "A service returned by SuseRegister has an invalid task: $pService";
                    }
                    elsif ( ${$pAny}{'TASK'} eq 'le' )
                    {
                        push @log, "According to SuseRegister a service does not need to be changed: $pService";
                    }
                    elsif ( ${$pAny}{'TASK'} eq 'a' )
                    {
                        push @log, "According to SuseRegister a service has to be added: $pService";
                        my @zCMD = ('zypper', '--non-interactive', 'addrepo',  '--name', "${$pAny}{'NAME'}", '--refresh',  "${$pAny}{'URL'}", "${$pAny}{'ALIAS'}" );
                        my @zCMDopt = ('zypper', '--non-interactive', 'modifyrepo', '--enable', '--refresh', '--priority', defined ${$pAny}{'URL'} ? ${$pAny}{'URL'} : 99 , "${$pAny}{'URL'}");
                        if ( system(@zCMD) == 0   &&   system(@zCMDopt) == 0 )
                        {
                            push @log, "Successfully added a new service: $pService";
                        }
                        else
                        {
                            push @log, "ERROR: Adding a new service failed: $pService";
                        }
                    }
                    elsif ( ${$pAny}{'TASK'} eq 'd' )
                    {
                        push @log, "According to SuseRegister a service has to be deleted: $pService";
                        my @zCMD = ('zypper', '--non-interactive', 'removerepo', "$pService");
                        if ( system(@zCMD) == 0 )
                        {
                            push @log, "Successfully deleted a service: $pService";
                        }
                        else
                        {
                            push @log, "ERROR: Could not delete a service: $pService";
                        }
                    }

                }
                elsif ( ${$pAny}{'TYPE'} eq 'nu' )
                {
                    push @log, "Handling a service of the type nu";

                    if ( not defined ${$pAny}{'TASK'}  ||  ${$pAny}{'TASK'} eq '' )
                    {
                        push @log, "A service returned by SuseRegister has an invalid task: $pService";
                    }
                    elsif ( ${$pAny}{'TASK'} eq 'ld' )
                    {
                        push @log, "According to SuseRegister a service should be left disabled: $pService";
                    }
                    elsif ( ${$pAny}{'TASK'} eq 'le' )
                    {
                        push @log, "According to SuseRegister a service should be left enabled: $pService";
                        push @log, "Now checking the catalogs of the service: $pService";

                        my @zCMD = ('zypper', '--non-interactive', 'refresh', '--services');
                        if ( system(@zCMD) == 0 )
                        {
                            push @log, "Successfully refreshed service: $pService";
                        }
                        else
                        {
                            push @log, "ERROR: Could not refresh service: $pService";
                        }
                        push @log, $self->checkcatalogs( ${$pAny}{'CATALOGS'}, $pService );
                    }
                    elsif ( ${$pAny}{'TASK'} eq 'a' )
                    {
                        push @log, "According to SuseRegister a service has to be added: $pService";

                        my @zCMD = ('zypper', '--non-interactive', 'addservice', ${$pAny}{'URL'}."?credentials=NCCcredentials", ${$pAny}{'ALIAS'});
                        if ( system(@zCMD) == 0 )
                        {
                            push @log, "Successfully added a new service: $pService";

                            my @zCMD = ('zypper', '--non-interactive', 'modifyservice', '--refresh', $pService);
                            if ( system(@zCMD) == 0 )
                            {
                                push @log, "Successfully enabled refreshing for service: $pService";
                            }
                            else
                            {
                                push @log, "ERROR: Could not enable refreshing of service: $pService";
                            }

                            push @log, "Now checking the catalogs of the service: $pService";

                            my @zrCMD = ('zypper', '--non-interactive', 'refresh', '--services');
                            if ( system(@zrCMD) == 0 )
                            {
                                push @log, "Successfully refreshed service: $pService";
                            }
                            else
                            {
                                push @log, "ERROR: Could not refresh service: $pService";
                            }
                            push @log, $self->checkcatalogs( ${$pAny}{'CATALOGS'}, $pService );
                        }
                        else
                        {
                            push @log, "Adding a new service failed: $pService";
                        }
                    }
                    elsif ( ${$pAny}{'TASK'} eq 'd' )
                    {
                        push @log, "According to SuseRegister a service has to be deleted: $pService";

                        my @zCMD = ('zypper', '--non-interactive', 'removeservice', $pService);
                        if ( system(@zCMD) )
                        {
                            push @log, "Successfully deleted a service: $pService";
                        }
                        else
                        {
                            push @log, "ERROR: Could not delete a service: $pService";
                        }
                    }
                }
                else
                {
                    push @log, "A service returned by SuseRegister has an unsupported type: $pService (${$pAny}{'TYPE'})";
                }
            } # end defined ${$pAny}{'TYPE'}
            else
            {
                push @log, "A service returned by SuseRegister has an invalid type";
            }
        }
    } # end foreach pService

    my @zCMD = ('zypper', '--non-interactive', 'refresh', '--services');
    if ( system(@zCMD) == 0 )
    {
        push @log, "Successfully refreshed all services";
    }
    else
    {
        push @log, "ERROR: Could not refresh all services";
    }

    return { 'log' => @log };
}


1;

#############################################################################
#############################################################################
#
# internal functions that should not be used directly by YaST (to prevent zypp deadlocks)
# they are here for documentation purposes or future use
#

# BEGIN { $TYPEINFO{get_ctx} = ["function", [ "map", "string", "any"]]; }
# sub get_ctx
# {
#    my $self = shift;

#    return $global_ctx;
# }

# BEGIN { $TYPEINFO{manageUpdateSources} = ["function", "void", [ "map", "string", "any"] ]; }
# sub manageUpdateSources
# {
#     my $self = shift;

#     return SUSE::SuseRegister::manageUpdateSources($global_ctx);
# }


# BEGIN { $TYPEINFO{addService} = ["function", ["list", "any"], [ "map", "string", "any"], [ "map", "string", "any"]]; }
# sub addService
# {
#     my $self = shift;
#     $global_ctx     = shift;
#     my $service = shift || undef;

#     return SUSE::SuseRegister::addService($global_ctx, $service);
# }


# BEGIN { $TYPEINFO{enableCatalog} = ["function", ["list", "any"], [ "map", "string", "any"], "string", [ "map", "string", "string"]]; }
# sub enableCatalog
# {
#     my $self = shift;
#     $global_ctx     = shift;
#     my $name    = shift || undef;
#     my $catalog = shift || undef;

#     return SUSE::SuseRegister::enableCatalog($global_ctx, $name, $catalog);
# }

# BEGIN { $TYPEINFO{deleteService} = ["function", ["list", "any"], [ "map", "string", "any"], [ "map", "string", "any"]]; }
# sub deleteService
# {
#     my $self = shift;
#     $global_ctx = shift;
#     my $service = shift || undef;

#     return SUSE::SuseRegister::deleteService($global_ctx, $service);
# }

# BEGIN { $TYPEINFO{disableCatalog} = ["function", ["list", "any"], [ "map", "string", "any"], "string", [ "map", "string", "string"]]; }
# sub disableCatalog
# {
#     my $self = shift;
#     $global_ctx     = shift;
#     my $name    = shift || undef;
#     my $catalog = shift || undef;

#     return SUSE::SuseRegister::disableCatalog($global_ctx, $name, $catalog);
# }


#
# Copyright (c) 2008 SUSE LINUX Products GmbH.  All rights reserved.
#
# Author: Michael Calmer <mc@suse.de>, 2008
# Editor: J. Daniel Schmidt <jdsn@suse.de>, 2008
#
# YSR.pm - interface for YaST to interact with SUSE::SuseRegister
#

package YSR;

use strict;
use SUSE::SuseRegister;
use Data::Dumper;

our %TYPEINFO;

my $global_ctx = {};


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
           $global_ctx->{args}->{key} = $value;
       }
       else
       {
           delete $global_ctx->{args}->{key};
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


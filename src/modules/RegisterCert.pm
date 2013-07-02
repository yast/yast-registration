#!/usr/bin/perl -w

package RegisterCert;

use strict;
use CaMgm;
use Date::Format;
use YaST::YCP qw(:LOGGING);
use Data::Dumper;

our %TYPEINFO;

BEGIN { $TYPEINFO{parseCertificate} = ["function", ["map", "string", "any"], "string"]; }
sub parseCertificate
{
    my $self = shift;
    my $file = shift;
    
    #my $file = "/etc/ssl/certs/YaST-CA.pem";
    my $result = {
                  SUBJECT => [],
                  ISSUER  => [],
                  STARTDATE => "",
                  ENDDATE   => "",
                  FINGERPRINT => ""
                 };
    
    if(!-e $file)
    {
        y2error("File not found ($file)");
        return undef;
    }
    
    my $certData = CaMgm::LocalManagement::getCertificate($file, $CaMgm::E_PEM);
    
    my $rdnlist = $certData->getSubjectDN()->getDN();
    
    my @SUBJECT = ();
    
    for(my $it = $rdnlist->begin();
        !$rdnlist->iterator_equal($it, $rdnlist->end());
        $rdnlist->iterator_incr($it))
    {
        my $hash = {};
        $hash->{$rdnlist->iterator_value($it)->getType()} = $rdnlist->iterator_value($it)->getValue();
        
        push @SUBJECT, $hash;
    }
    
    $result->{SUBJECT} = \@SUBJECT;
    
    $rdnlist = $certData->getIssuerDN()->getDN();
    
    my @ISSUER = ();
    
    for(my $it = $rdnlist->begin();
        !$rdnlist->iterator_equal($it, $rdnlist->end());
        $rdnlist->iterator_incr($it))
    {
        my $hash = {};
        $hash->{$rdnlist->iterator_value($it)->getType()} = $rdnlist->iterator_value($it)->getValue();
        
        push @ISSUER, $hash;
    }
    
    $result->{ISSUER} = \@ISSUER;
    
    my $datestr = time2str('%Y-%m-%d %X GMT', $certData->getStartDate());
    
    $result->{STARTDATE}   = $datestr;
    
    $datestr = time2str('%Y-%m-%d %X GMT', $certData->getEndDate());
    
    $result->{ENDDATE}     = $datestr;
    $result->{FINGERPRINT} = $certData->getFingerprint();
    
    y2milestone("Return certificate data: ".Data::Dumper->Dump([$result]));
    return $result;    
}





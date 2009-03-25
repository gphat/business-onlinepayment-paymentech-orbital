package Business::OnlinePayment::PaymenTech;
use strict;

our $VERSION = '1.1.0';
our $AUTHORITY = 'cpan:GPHAT';

=head1 NAME

Business::OnlinePayment::PaymenTech - PaymenTech backend for Business::OnlinePayment

=head1 SYNPOSIS

  my %options;
  $options{'merchantid'} = '1234';
  my $tx = new Business::OnlinePayment('PaymenTech', %options);
  $tx->content(
    username        => 'username',
    password        => 'pass',
    invoice_number  => $orderid,
    trace_number    => $trace_num, # Optional
    action          => 'Authorization Only',
    cvv2val         => 123,
    card_number     => '1234123412341234',
    exp_date        => '0410',
    address         => '123 Test Street',
    name            => 'Test User',
    amount          => 100 # $1.00
  );
  $tx->submit();

  if($tx->is_success()) {
    print "Card processed successfully: ".$tx->authorization()."\n";
  } else {
    print "Card was rejected: ".$tx->error_message()."\n";
  }

=head1 SUPPORTED ACTIONS

Authorization Only, Authorization and Capture, Capture, Credit

=head1 DESCRIPTION

Business::OnlinePayment::PaymenTech allows you to utilize PaymenTech's
Orbital SDK credit card services.  You will need to install the Perl Orbital
SDK for this to work.

For detailed information see L<Business::OnlinePayment>.

=head1 NOTES

There are a few rough edges to this module, but having it significantly eased
a transition from one processor to another.

=head2 DEFAULTS

=over

=item time zone defaults to 706 (Central)

=item BIN defaults 001

=back
 
Some extra getters are provided.  They are:

 avs_response   - Get the AVS response
 cvv2_response  - Get the CVV2 response
 transaction_id - Get the PaymenTech assigned Transaction Id

=cut

use base qw(Business::OnlinePayment);

use Paymentech::SDK;
use Paymentech::eCommerce::RequestBuilder 'requestBuilder';
use Paymentech::eCommerce::RequestTypes qw (MOTO_AUTHORIZE_REQUEST CC_MARK_FOR_CAPTURE_REQUEST ECOMMERCE_REFUND_REQUEST);
use Paymentech::eCommerce::TransactionProcessor ':alias';

sub set_defaults {
    my $self = shift();

    $self->{'_content'} = {};

    $self->build_subs(
        qw(avs_response cvv2_response transaction_id card_proc_resp)
    );
}

sub submit {
    my $self = shift();

    my %content = $self->content();

    my $req;
    if($content{'action'} eq 'Authorization Only') {
        $req = requestBuilder()->make(MOTO_AUTHORIZE_REQUEST());
        $req->MessageType('A');
        $self->_addBillTo($req);

        $req->CurrencyCode('840');
        $req->Exp($content{'exp_date'});

    } elsif($content{'action'} eq 'Capture') {
        $req = requestBuilder()->make(CC_MARK_FOR_CAPTURE_REQUEST());
        $req->TxRefNum($content{'tx_ref_num'});
    } elsif($content{'action'} eq 'Force Authorization Only') {
        # ?
    } elsif($content{'action'} eq 'Authorization and Capture') {
        $req = requestBuilder()->make(MOTO_AUTHORIZE_REQUEST());
        $self->_addBillTo($req);
        # Authorize and Capture
        $req->MessageType('AC');
        $req->CurrencyCode('840');

        $req->Exp($content{'exp_date'});

    } elsif($content{'action'} eq 'Credit') {
        $req = requestBuilder()->make(ECOMMERCE_REFUND_REQUEST());
        $req->CurrencyCode('840');
        $req->Amount($content{'amount'});
    } else {
        die('Unknown Action: '.$content{'action'}."\n");
    }

    $req->BIN($content{'BIN'} || '000001');
    $req->MerchantID($self->{'merchantid'});
    if(exists($content{'trace_number'}) && $content{'trace_number'} =~ /^\d+$/)) {
        $req->traceNumber($content{'trace_number'});
    }
    $req->OrderID($content{'invoice_number'});
    $req->AccountNum($content{'card_number'});
    $req->Amount(sprintf("%012d", $content{'amount'}));
    $req->TzCode($content{'TzCode'} || '706');
    $req->Comments($content{'comments'}, || '');

    $self->{'request'} = $req;

    $self->_post();

    $self->_processResponse();
}

sub _post {
    my $self = shift();

    my %content = $self->content();

    my $gw_resp = gatewayTP()->process($self->{'request'});
}

sub _processResponse {
    my $self = shift();

    my $resp = $self->{'request'}->response();

    unless(defined($resp)) {
        $self->is_success(0);
        $self->error_message($self->error_message()." No response.");
        return;
    }

    if($self->test_transaction()) {
        print STDERR $resp->raw();
    }

    $self->transaction_id($resp->value('TxRefNum'));
    $self->cvv2_response($resp->CVV2ResponseCode());
    $self->avs_response($resp->AVSResponseCode());
    $self->authorization($resp->value('AuthCode'));
    $self->error_message($resp->status());

    if(!$resp->approved()) {
        $self->is_success(0);
        return;
    }

    $self->is_success(1);
}

sub _addBillTo {
    my $self = shift();
    my $req = shift();

    my %content = $self->content();

    $req->AVSname($content{'name'});
    $req->AVSaddress1($content{'address'});
    $req->AVSaddress2($content{'address2'});
    $req->AVScity($content{'city'});
    $req->AVSstate($content{'state'});
    $req->AVSzip($content{'zip'});
    $req->AVScountryCode($content{'country'});
    $req->AVSphoneNum($content{'phone_number'});
}

=head1 AUTHOR

Cory 'G' Watson <gphat@cpan.org>

=head2 CONTRIBUTORS

Garth Sainio

=head1 SEE ALSO

perl(1), L<Business::OnlinePayment>.

=head1 COPYRIGHT AND LICENSE

Copyright 2008 by Magazines.com, LLC

You can redistribute and/or modify this code under the same terms as Perl
itself.

=cut
1;

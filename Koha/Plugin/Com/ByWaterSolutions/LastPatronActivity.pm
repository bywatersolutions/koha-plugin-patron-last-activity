package Koha::Plugin::Com::ByWaterSolutions::LastPatronActivity;

## It's good practive to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Context;
use C4::Members;
use C4::Auth;
use Koha::DateUtils qw( output_pref dt_from_string );
use Koha::Database;

use Text::CSV::Slurp;

## Here we set our plugin version
our $VERSION = "{VERSION}";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name   => 'Last Patron Activity',
    author => 'Kyle M Hall, ByWater Solutions',
    description =>
'This report lists the last the date of a patrons last activity for all patrons enrolled within a given date range.',
    date_authored   => '2009-01-27',
    date_updated    => '2009-01-27',
    minimum_version => '3.16000000',
    maximum_version => undef,
    version         => $VERSION,
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

## The existance of a 'report' subroutine means the plugin is capable
## of running a report. This example report can output a list of patrons
## either as HTML or as a CSV file. Technically, you could put all your code
## in the report method, but that would be a really poor way to write code
## for all but the simplest reports
sub report {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('output') ) {
        $self->report_step1();
    }
    else {
        $self->report_step2();
    }
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    return 1;
}

## These are helper functions that are specific to this plugin
## You can manage the control flow of your plugin any
## way you wish, but I find this is a good approach
sub report_step1 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'report-step1.tt' } );

    $template->param(
        current_branch   => C4::Context->userenv->{branch},
    );

    print $cgi->header();
    print $template->output();
}

sub report_step2 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $dbh = C4::Context->dbh;

    my $branch   = $cgi->param('branch');
    my $category = $cgi->param('categorycode');
    my $output   = $cgi->param('output');

    my $from = dt_from_string( $cgi->param('from') )->ymd();
    my $to   = dt_from_string( $cgi->param('to') )->ymd();

    my $params;
    $params->{branchcode}   = $branch   if $branch;
    $params->{categorycode} = $category if $category;
    $params->{dateenrolled} = { '>=' => $from, '<=' => $to };

    my $schema = Koha::Database->new()->schema();
    #$schema->storage->debug(1);

    my @borrowers = $schema->resultset('Borrower')->search(
        $params,
        {
            order_by     => 'cardnumber',
            result_class => 'DBIx::Class::ResultClass::HashRefInflator',
        }
    );

    my $query = "SELECT datetime FROM statistics WHERE borrowernumber = ? ORDER BY datetime DESC LIMIT 1";

    map { ( $_->{last_activity} ) = $dbh->selectrow_array( $query, undef, $_->{borrowernumber} ) } @borrowers;

    my $filename;
    if ( $output eq "csv" ) {
        print $cgi->header( -attachment => 'borrowers.csv' );
        print Text::CSV::Slurp->create( input => \@borrowers );
    }
    else {
        print $cgi->header();
        $filename = 'report-step2-html.tt';

        my $template = $self->get_template( { file => $filename } );

        my $library = Koha::Libraries->find($branch);
        $template->param(
            date_ran     => output_pref(dt_from_string),
            results_loop => \@borrowers,
            branch       => $library->branchname,
            category     => $category,
        );

        print $template->output();
    }

}

1;

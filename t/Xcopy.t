# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use strict;
use warnings;

use Test::More qw(no_plan);

use File::Xcopy;
my $class = 'File::Xcopy';
my $obj = $class->new; 

isa_ok($obj, $class);

# use Data::Dumper;
# print Dumper($obj); 

my @md = @File::Xcopy::EXPORT_OK; 
foreach my $m (@md) {
    ok($obj->can($m), "$class->can('$m')");
}

my $d1 = '/opt/orasw/dba/cgi/subprgs';
my $d2 = '/opt/orasw/dba/cgi/subprgs/baks'; 
$obj->from_dir($d1);
$obj->to_dir($d2); 
$obj->action('test');
$obj->fn_pat('^lib_df51t5.*(\.pl|\.txt)$');
$obj->param('s',0);    # recursive 
$obj->xcopy;


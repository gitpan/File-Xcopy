package File::Xcopy;

use 5.005_64;
use strict;
use vars qw($AUTOLOAD);
use Carp;
our(@ISA, @EXPORT, @EXPORT_OK, $VERSION, %EXPORT_TAGS);
$VERSION = '0.06';


# require Exporter;
# @ISA = qw(Exporter);
@EXPORT = qw();
@EXPORT_OK = qw(xcp xmv xcopy xmove find_files list_files);
%EXPORT_TAGS = ( 
  all => [@EXPORT_OK] 
);

use File::Find; 
use Fax::DataFax::Subs qw(:echo_msg disp_param);

sub xcopy;
sub xmove;
sub xcp;
sub xmv;

=head1 NAME

File::Xcopy - copy files after comparing them.

=head1 SYNOPSIS

  	use File::Xcopy;

	xcopy("file1","file2", "action");
  	xcopy("from_dir", "to_dir", "action", "file_name_pattern");

	xcp("file1","file2", "action");
  	xcp("from_dir", "to_dir", "action", "file_name_pattern");

	my $xcp = File::Xcopy->new(log_file=>"file_name");

=head1 DESCRIPTION

The File::Xcopy module provides two basic functions, C<xcopy> and
C<xmove>, which are useful for coping and/or moving a file or
files in a directory from one place to another. It mimics some of 
behaviours of C<xcopy> in DOS but with more functions and options. 


The differences between C<xcopy> and C<copy> are

=over 4

=item *

C<xcopy> searches files based on file name pattern if the 
pattern is specified.

=item *

C<xcopy> compares the timestamp and size of a file before it copies.

=item *

C<xcopy> takes different actions if you tell it to.

=back

=cut

{  # Encapsulated class data
    my %_attr_data =                        # default accessibility
    (
      _from_dir   =>['$','read/write',''],  # directory 1
      _to_dir     =>['$','read/write',''],  # directory 2 
      _fn_pat     =>['$','read/write',''],  # file name pattern
      _action     =>['$','read/write',''],  # action 
      _param      =>['%','read/write',{}],  # dynamic parameters
    );
    sub _accessible {
        my ($self, $attr, $mode) = @_;
        if (exists $_attr_data{$attr}) {
            return $_attr_data{$attr}[1] =~ /$mode/;
        } 
    }
    # classwide default value for a specified object attributes
    sub _default_for {
        my ($self, $attr) = @_;
        if (exists $_attr_data{$attr}) {
            return $_attr_data{$attr}[2];
        } 
    }
    # list of names of all specified object attributes

    sub _standard_keys {
        my $self = shift;
        # ($self->SUPER::_standard_keys, keys %_attr_data);
        (keys %_attr_data);
    }
    sub _accs_type {
        my ($self, $attr) = @_;
        if (exists $_attr_data{$attr}) {
            return $_attr_data{$attr}[0];
        } 
    }
}

=head2 The Constructor new(%arg)

Without any input, i.e., new(), the constructor generates an empty
object with default values for its parameters.

If any argument is provided, the constructor expects them in
the name and value pairs, i.e., in a hash array.

=cut

sub new {
    my $caller        = shift;
    my $caller_is_obj = ref($caller);
    my $class         = $caller_is_obj || $caller;
    my $self          = bless {}, $class;
    my %arg           = @_;   # convert rest of inputs into hash array
    # print join "|", $caller,  $caller_is_obj, $class, $self, "\n";
    foreach my $attrname ( $self->_standard_keys() ) {
        my ($argname) = ($attrname =~ /^_(.*)/);
        # print "attrname = $attrname: argname = $argname\n";
        if (exists $arg{$argname}) {
            $self->{$attrname} = $arg{$argname};
        } elsif ($caller_is_obj) {
            $self->{$attrname} = $caller->{$attrname};
        } else {
            $self->{$attrname} = $self->_default_for($attrname);
        }
        # print $attrname, " = ", $self->{$attrname}, "\n";
    }
    # $self->debug(5);
    return $self;
}


# implement other get_... and set_... method (create as neccessary)
sub AUTOLOAD {
    no strict "refs";
    my ($self, $v1, $v2) = @_;
    (my $sub = $AUTOLOAD) =~ s/.*:://;
    my $m = $sub;
    (my $attr = $sub) =~ s/(get_|set_)//;
        $attr = "_$attr";
    # print join "|", $self, $v1, $v2, $sub, $attr,"\n";
    my $type = $self->_accs_type($attr);
    croak "ERR: No such method: $AUTOLOAD.\n" if !$type;
    my  $v = "";
    my $msg = "WARN: no permission to change";
    if ($type eq '$') {           # scalar method
        $v  = "\n";
        $v .= "    my \$s = shift;\n";
        $v .= "    croak \"ERR: Too many args to $m.\" if \@_ > 1;\n";
        if ($self->_accessible($attr, 'write')) {
            $v .= "    \@_ ? (\$s->{$attr}=shift) : ";
            $v .= "return \$s->{$attr};\n";
        } else {
            $v .= "    \@_ ? (carp \"$msg $m.\n\") : ";
            $v .= "return \$s->{$attr};\n";
        }
    } elsif ($type eq '@') {      # array method
        $v  = "\n";
        $v .= "    my \$s = shift;\n";
        $v .= "    my \$a = \$s->{$attr}; # get array ref\n";
        $v .= "    if (\@_ && (ref(\$_[0]) eq 'ARRAY' ";
        $v .= "|| \$_[0] =~ /.*=ARRAY/)) {\n";
        $v .= "        \$s->{$attr} = shift; return;\n    }\n";
        $v .= "    my \$i;     # array index\n";
        $v .= "    \@_ ? (\$i=shift) : return \$a;\n";
        $v .= "    croak \"ERR: Too many args to $m.\" if \@_ > 1;\n";
        if ($self->_accessible($attr, 'write')) {
            $v .= "    \@_ ? (\${\$a}[\$i]=shift) : ";
            $v .= "return \${\$a}[\$i];\n";
        } else {
            $v .= "    \@_ ? (carp \"$msg $m.\n\") : ";
            $v .= "return \${\$a}[\$i];\n";
        }
    } else {                      # assume hash method: type = '%'
        $v  = "\n";
        $v .= "    my \$s = shift;\n";
        $v .= "    my \$a = \$s->{$attr}; # get hash array ref\n";
        $v .= "    if (\@_ && (ref(\$_[0]) eq 'HASH' ";
        $v .= " || \$_[0] =~ /.*=HASH/)) {\n";
        $v .= "        \$s->{$attr} = shift; return;\n    }\n";
        $v .= "    my \$k;     # hash array key\n";
        $v .= "    \@_ ? (\$k=shift) : return \$a;\n";
        $v .= "    croak \"ERR: Too many args to $m.\" if \@_ > 1;\n";
        if ($self->_accessible($attr, 'write')) {
            $v .= "    \@_ ? (\${\$a}{\$k}=shift) : ";
            $v .= "return \${\$a}{\$k};\n";
        } else {
            $v .= "    \@_ ? (carp \"$msg $m.\n\") : ";
            $v .= "return \${\$a}{\$k};\n";
        }
    }
    # $self->echoMSG("sub $m {$v}\n",100);
    *{$sub} = eval "sub {$v}";
    goto &$sub;
}

sub DESTROY {
    my ($self) = @_;
    # clean up base classes
    return if !@ISA;
    foreach my $parent (@ISA) {
        next if $self::DESTROY{$parent}++;
        my $destructor = $parent->can("DESTROY");
        $self->$destructor() if $destructor;
    }
}


=head3 xcopy($from, $to, $act, $pat, $par)

Input variables:

  $from - a source file or directory 
  $to   - a target directory or file name 
  $act  - action: 
       report|test - test run
       copy|CP - copy files from source to target only if
                 1) the files do not exist or 
                 2) newer than the existing ones
                 This is default.
  overwrite|OW - copy files from source to target even if
                 the files exist and newer than the source files 
       move|MV - same as in copy except it removes from source the  
                 following files: 
                 1) files are exactly the same (size and time stamp)
                 2) files are copied successfully
     update|UD - copy files only if
                 1) the file exists in the target and
                 2) different from the source in size and time stamp.
  $pat - file name match pattern, default to {.+}
  $par - parameter array
    log_file - log file name with full path
    

  source       Specifies the file(s) to copy.
  destination  Specifies the location and/or name of new files.
  /A           Copies only files with the archive attribute set,
               doesn't change the attribute.
  /M           Copies only files with the archive attribute set,
               turns off the archive attribute.
  /D:m-d-y     Copies files changed on or after the specified date.
               If no date is given, copies only those files whose
               source time is newer than the destination time.
  /EXCLUDE:file1[+file2][+file3]...
               Specifies a list of files containing strings.  When any of the
               strings match any part of the absolute path of the file to be
               copied, that file will be excluded from being copied.  For
               example, specifying a string like \obj\ or .obj will exclude
               all files underneath the directory obj or all files with the
               .obj extension respectively.
  /P           Prompts you before creating each destination file.
  /S           Copies directories and subdirectories except empty ones.
  /E           Copies directories and subdirectories, including empty ones.
               Same as /S /E. May be used to modify /T.
  /V           Verifies each new file.
  /W           Prompts you to press a key before copying.
  /C           Continues copying even if errors occur.
  /I           If destination does not exist and copying more than one file,
               assumes that destination must be a directory.
  /Q           Does not display file names while copying.
  /F           Displays full source and destination file names while copying.
  /L           Displays files that would be copied.
  /H           Copies hidden and system files also.
  /R           Overwrites read-only files.
  /T           Creates directory structure, but does not copy files. Does not
               include empty directories or subdirectories. /T /E includes
               empty directories and subdirectories.
  /U           Copies only files that already exist in destination.
  /K           Copies attributes. Normal Xcopy will reset read-only attributes.
  /N           Copies using the generated short names.
  /O           Copies file ownership and ACL information.
  /X           Copies file audit settings (implies /O).
  /Y           Suppresses prompting to confirm you want to overwrite an
               existing destination file.
  /-Y          Causes prompting to confirm you want to overwrite an
               existing destination file.
  /Z           Copies networked files in restartable mode.

Variables used or routines called: None.

How to use:

  use File::Xcopy;
  my $obj = File::Xcopy->new;
  # update all the files with .txt extension if they exists in /tgt/dir
  $obj->xcopy('/src/files', '/tgt/dir', 'OW', '\.txt$'); 

  use File:Xcopy qw(xcopy); 
  xcopy('/src/files', '/tgt/dir', 'OW', '\.txt$'); 

Return: ($n, $m). 

  $n - number of files copied or moved. 
  $m - total number of files matched

=cut

sub xcopy {
    my $self = shift;
    my $class = ref($self)||$self;
    my($from,$to, $act, $pat, $par) = @_;
    $from = $self->from_dir if ! $from; 
    $to   = $self->to_dir   if ! $to; 
    $act  = $self->action   if ! $act; 
    $pat  = $self->fn_pat   if ! $pat; 
    $par  = $self->param    if ! $par; 
    croak "ERR: source dir or file not specified.\n" if ! $from; 
    croak "ERR: target dir not specified.\n"         if ! $to; 
    croak "ERR: could not find src dir - $from.\n"   if ! -d $from;
    croak "ERR: could not find tgt dir - $to.\n"     if ! -d $to  ;
    $act = 'copy' if !$act; 
    my ($re, $n, $m, $t);
    if ($pat) { $re = qr {$pat}; } else { $re = qr {.+}; } 
    # $$re = qr {^lib_df51t5.*(\.pl|\.txt)$};
    my $far = bless [], $class;      # from array ref 
    my $tar = bless [], $class;      # to   array ref
    # get file name list
    if ($par && exists ${$par}{s}) {  # search sub-dir as well 
        $far = $self->find_files($from, $re); 
        $tar = $self->find_files($to,   $re); 
    } else {                          # only files in $from
        $far = $self->list_files($from, $re);
        $tar = $self->list_files($to,   $re); 
    }
    # convert array into hash 
    my $fhr = $self->file_stat($from, $far);
    my $thr = $self->file_stat($to,   $tar); 

    $self->disp_param($fhr); 
    $self->disp_param($thr); 

    foreach my $f (keys %{$fhr}) {

    }
    return ($n, $m); 
}

sub xmove {
    my $s = shift;
    $s->action('move');
    $s->xcopy(@_);  
};

=head2 find_files($dir,$re)

Input variables:

  $dir - directory name in which files and sub-dirs will be searched
  $re  - file name pattern to be matched. 

Variables used or routines called: None.

How to use:

  use File::Xcopy;
  my $fc = File::Xcopu->new;
  # find all the pdf files and stored in the array ref $ar
  my $ar = $fc->find_files('/my/src/dir', '\.pdf$'); 

Return: $ar - array ref and can be accessed as ${$ar}[$i]{$itm}, 
where $i is sequence number, and $itm are

  file - file name without dir 
  pdir - parent dir for the file
  path - full path for the file

This method resursively finds all the matched files in the directory 
and its sub-directories. It uses C<finddepth> method from 
File::Find(1) module. 

=cut

sub find_files {
    my $self = shift;
    my $cls  = ref($self)||$self; 
    my ($dir, $re) = @_;
    my $ar = bless [], $cls; 
    my $sub = sub { 
        (/$re/)
        && (push @{$ar}, {file=>$_, pdir=>$File::Find::dir,
           path=>$File::Find::name});
    };
    finddepth($sub, $dir);
    return $ar; 
}

=head2 list_files($dir,$re)

Input variables:

  $dir - directory name in which files will be searched
  $re  - file name pattern to be matched. 

Variables used or routines called: None.

How to use:

  use File::Xcopy;
  my $fc = File::Xcopu->new;
  # find all the pdf files and stored in the array ref $ar
  my $ar = $fc->list_files('/my/src/dir', '\.pdf$'); 

Return: $ar - array ref and can be accessed as ${$ar}[$i]{$itm}, 
where $i is sequence number, and $itm are

  file - file name without dir 
  pdir - parent dir for the file
  path - full path for the file

This method only finds the matched files in the directory and will not
search sub directories. It uses C<readdir> to get file names.  

=cut

sub list_files {
    my $self = shift;
    my $cls  = ref($self)||$self; 
    my $ar = bless [], $cls; 
    my ($dir, $re) = @_;
    opendir DD, $dir or croak "ERR: open dir - $dir: $!\n";
    my @a = grep $re , readdir DD; 
    closedir DD; 
    foreach my $f (@a) { 
        push @{$ar}, {file=>$f, pdir=>$dir, rdir=>$f,  
            path=>"$dir/$f"};
    }
    return $ar; 
}

=head2 file_stat($dir,$ar)

Input variables:

  $dir - directory name in which files will be searched
  $ar  - array ref returned from C<find_files> or C<list_files>
         method. 

Variables used or routines called: None.

How to use:

  use File::Xcopy;
  my $fc = File::Xcopu->new;
  # find all the pdf files and stored in the array ref $ar
  my $ar = $fc->find_files('/my/src/dir', '\.pdf$'); 
  my $br = $fc->file_stat('/my/src/dir', $ar); 

Return: $br - hash array ref and can be accessed as ${$ar}{$k}{$itm}, 
where $k is C<rdir> and the $itm are 

  size - file size in bytes
  time - modification time in Perl time
  file - file name
  pdir - parent directory


This method also adds the following elements additional to 'file',
'pdir', and 'path' in the $ar array:

  prop - file stat array
  rdir - relative file name to the $dir
  
The following lists the elements in the stat array: 

  file stat array - ${$far}[$i]{prop}: 
   0 dev      device number of filesystem
   1 ino      inode number
   2 mode     file mode  (type and permissions)
   3 nlink    number of (hard) links to the file
   4 uid      numeric user ID of file's owner
   5 gid      numeric group ID of file's owner
   6 rdev     the device identifier (special files only)
   7 size     total size of file, in bytes
   8 atime    last access time in seconds since the epoch
   9 mtime    last modify time in seconds since the epoch
  10 ctime    inode change time (NOT creation time!) in seconds 
              sinc e the epoch
  11 blksize  preferred block size for file system I/O
  12 blocks   actual number of blocks allocated

This method converts the array into a hash array and add additional 
elements to the input array as well.

=cut

sub file_stat {
    my $s = shift;
    my $c = ref($s)||$s; 
    my ($dir, $ar) = @_; 

    my $br = bless {}, $c; 
    my ($k, $fsz, $mtm); 
    for my $i (0..$#{$ar}) {
        $k = ${$ar}[$i]{path}; 
        ${$ar}[$i]{prop} = [stat $k];
        $k =~ s{$dir}{\.};
        ${$ar}[$i]{rdir} = $k; 
        $fsz = ${$ar}[$i]{prop}[7]; 
        $mtm = ${$ar}[$i]{prop}[9]; 
        ${$br}{$k} = {file=>${$ar}[$i]{file}, size=>$fsz, time=>$mtm,
            pdir=>${$ar}[$i]{pdir}};
    }
    return $br; 
}

*xcp = \&xcopy;
*xmv = \&xmove;


1;

__END__

=head1 AUTHOR

File::Xcopy is written by Hanming Tu I<E<lt>hanming_tu@yahoo.comE<gt>>.

=cut


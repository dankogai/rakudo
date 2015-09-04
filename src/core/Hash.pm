my class Hash { # declared in BOOTSTRAP
    # my class Hash is EnumMap {
    #     has Mu $!descriptor;

    multi method Hash() {
        self
    }

    multi method AT-KEY(Hash:D: \key) is rw {
        my Mu $storage := nqp::getattr(self, EnumMap, '$!storage');
        $storage := nqp::bindattr(self, EnumMap, '$!storage', nqp::hash())
            unless nqp::defined($storage);
        my str $skey = nqp::istype(key, Str) ?? key !! key.Str;
        if nqp::existskey($storage, $skey) {
            nqp::atkey($storage, $skey);
        }
        else {
            nqp::p6bindattrinvres(
                (my \v := nqp::p6scalarfromdesc($!descriptor)),
                Scalar,
                '$!whence',
                -> { nqp::bindkey($storage, $skey, v) }
            );
        }
    }

    multi method ASSIGN-KEY(Hash:D: \key, Mu \assignval) {
        my Mu $storage := nqp::getattr(self, EnumMap, '$!storage');
        $storage := nqp::bindattr(self, EnumMap, '$!storage', nqp::hash())
            unless nqp::defined($storage);
        my str $key = nqp::istype(key, Str) ?? key !! key.Str;
        nqp::existskey($storage, $key)
            ?? (nqp::atkey($storage, $key) = assignval)
            !! nqp::bindkey($storage, $key,
                nqp::p6scalarfromdesc($!descriptor) = assignval)
    }

    method BIND-KEY(Hash:D: \key, Mu \bindval) is rw {
        my Mu $storage := nqp::getattr(self, EnumMap, '$!storage');
        $storage := nqp::bindattr(self, EnumMap, '$!storage', nqp::hash())
            unless nqp::defined($storage);
        my str $key = nqp::istype(key, Str) ?? key !! key.Str;
        nqp::bindkey($storage, $key, bindval)
    }

    multi method perl(Hash:D \SELF:) {
        if not %*perlseen<TOP> { my %*perlseen = :TOP ; return self.perl }
        if %*perlseen{self.WHICH} { %*perlseen{self.WHICH} = 2; return "Hash_{self.WHERE}" }
        %*perlseen{self.WHICH} = 1;
        my $result = '$' x nqp::iscont(SELF) ~
        '{' ~ SELF.pairs.sort.map({.perl}).join(', ') ~ '}';
        $result = "(my \\Hash_{self.WHERE} = $result)" if %*perlseen{self.WHICH}:delete == 2;
        $result;
    }

    multi method gist(Hash:D:) {
        if not %*gistseen<TOP> { my %*gistseen = :TOP ; return self.gist }
        if %*gistseen{self.WHICH} { %*gistseen{self.WHICH} = 2; return "Hash_{self.WHERE}" }
        %*gistseen{self.WHICH} = 1;
        my $result = self.pairs.sort.map( -> $elem {
            given ++$ {
                when 101 { '...' }
                when 102 { last }
                default  { $elem.gist }
            }
        } ).join: ', ';
        $result = "(\\Hash_{self.WHERE} = $result)" if %*gistseen{self.WHICH}:delete == 2;
        $result;
    }

    multi method DUMP(Hash:D: :$indent-step = 4, :%ctx?) {
        return DUMP(self, :$indent-step) unless %ctx;

        my Mu $attrs := nqp::list();
        nqp::push($attrs, '$!descriptor');
        nqp::push($attrs,  $!descriptor );
        nqp::push($attrs, '$!storage'   );
        nqp::push($attrs,  nqp::getattr(nqp::decont(self), EnumMap, '$!storage'));
        self.DUMP-OBJECT-ATTRS($attrs, :$indent-step, :%ctx);
    }

    method STORE_AT_KEY(\key, Mu $x) is rw {
        my $v := nqp::p6scalarfromdesc($!descriptor);
        nqp::findmethod(EnumMap, 'STORE_AT_KEY')(self, key, $v = $x);
    }

    # introspection
    method name() {
        my $d := $!descriptor;
        nqp::isnull($d) ?? Str !! $d.name()
    }
    method keyof () { Any }
    method of() {
        my $d := $!descriptor;
        nqp::isnull($d) ?? Mu !! $d.of;
    }
    method default() {
        my $d := $!descriptor;
        nqp::isnull($d) ?? Any !! $d.default;
    }
    method dynamic() {
        my $d := $!descriptor;
        nqp::isnull($d) ?? Bool !! so $d.dynamic;
    }

    multi method DELETE-KEY(Hash:U:) { Nil }
    multi method DELETE-KEY(Str() \key) {
        my Mu $val = self.AT-KEY(key);
        nqp::deletekey(
            nqp::getattr(self, EnumMap, '$!storage'),
            nqp::unbox_s(key)
        );
        $val;
    }
    multi method DELETE-KEY(Str() \key, :$SINK!) {
        nqp::deletekey(
            nqp::getattr(self, EnumMap, '$!storage'),
            nqp::unbox_s(key)
        );
        Nil;
    }

    method push(*@values) {
        fail X::Cannot::Lazy.new(:action<push>, :what(self.^name))
          if @values.is-lazy;
        my $previous;
        my $has_previous;
        for @values -> $e {
            if $has_previous {
                self!_push_construct($previous, $e);
                $has_previous = 0;
            } elsif $e.^isa(Enum) {
                self!_push_construct($e.key, $e.value);
            } else {
                $previous = $e;
                $has_previous = 1;
            }
        }
        if $has_previous {
            warn "Trailing item in Hash.push";
        }
        self
    }

    proto method classify-list(|) { * }
    # XXX GLR possibly more efficient taking an Iterable, not a @list
    multi method classify-list( &test, @list, :&as ) {
        fail X::Cannot::Lazy.new(:action<classify>) if @list.is-lazy;
        if @list {

            # multi-level classify
            if nqp::istype(test(@list[0]),Iterable) {
                @list.map: -> $l {
                    my @keys  = test($l);
                    my $last := @keys.pop;
                    my $hash  = self;
                    $hash = $hash{$_} //= self.new for @keys;
                    nqp::push(
                      nqp::getattr(nqp::decont($hash{$last} //= []), List, '$!reified'),
                      &as ?? as($l) !! $l
                    );
                }
            }

            # simple classify to store a specific value
            elsif &as {
                @list.map: {
                    nqp::push(
                      nqp::getattr(nqp::decont(self{test $_} //= []), List, '$!reified'),
                      as($_)
                    )
                }
            }

            # just a simple classify
            else {
                @list.map: {
                    nqp::push(
                      nqp::getattr(nqp::decont(self{test $_} //= []), List, '$!reified'),
                      $_
                    )
                }
            }
        }
        self;
    }
    multi method classify-list( %test, $list, |c ) {
        self.classify-list( { %test{$^a} }, $list, |c );
    }
    multi method classify-list( @test, $list, |c ) {
        self.classify-list( { @test[$^a] }, $list, |c );
    }

    proto method categorize-list(|) { * }
    # XXX GLR possibly more efficient taking an Iterable, not a @list
    # XXX GLR replace p6listitems op use
    # XXX GLR I came up with simple workarounds but this can probably
    #         be done more efficiently better.
    multi method categorize-list( &test, @list, :&as ) {
       fail X::Cannot::Lazy.new(:action<categorize>) if @list.is-lazy;
       if @list {
           # multi-level categorize
           if nqp::istype(test(@list[0])[0],Iterable) {
               @list.map: -> $l {
                   my $value := &as ?? as($l) !! $l;
                   for test($l) -> $k {
                       my @keys = @($k);
                       my $last := @keys.pop;
                       my $hash  = self;
                       $hash = $hash{$_} //= self.new for @keys;
                       $hash{$last}.push: $value;
                   }
               }
           } else {    
           # just a simple categorize
               @list.map: -> $l {
                  my $value := &as ?? as($l) !! $l;
                  (self{$_} //= []).push: $value for test($l);
               }
               # more efficient (maybe?) nom version that might
               # yet be updated for GLR
               # @list.map: -> $l {
               #     my $value := &as ?? as($l) !! $l;
               #     nqp::push(
               #       nqp::p6listitems(nqp::decont(self{$_} //= [])), $value )
               #       for test($l);
           }
       }
       self;
    }
    multi method categorize-list( %test, $list ) {
        self.categorize-list( { %test{$^a} }, $list );
    }
    multi method categorize-list( @test, $list ) {
        self.categorize-list( { @test[$^a] }, $list );
    }

    # push a value onto a hash slot, constructing an array if necessary
    method !_push_construct(Mu $key, Mu $value) {
        if self.EXISTS-KEY($key) {
            if self.{$key}.^isa(Array) {
                self.{$key}.push($value);
            } else {
                self.{$key} = [ self.{$key}, $value ];
            }
        } else {
            self.{$key} = $value;
        }
    }

    my role TypedHash[::TValue] does Associative[TValue] {
        method AT-KEY(::?CLASS:D: Str() $key) is rw {
            if self.EXISTS-KEY($key) {
                nqp::findmethod(EnumMap, 'AT-KEY')(self, $key);
            }
            else {
                nqp::p6bindattrinvres(
                    (my \v := nqp::p6scalarfromdesc(nqp::getattr(self, Hash, '$!descriptor'))),
                    Scalar,
                    '$!whence',
                    -> { nqp::findmethod(EnumMap, 'STORE_AT_KEY')(self, $key, v) }
                );
            }
        }
        method STORE_AT_KEY(Str \key, TValue $x) is rw {
            my $v :=
              nqp::p6scalarfromdesc(nqp::getattr(self, Hash, '$!descriptor'));
            nqp::findmethod(EnumMap, 'STORE_AT_KEY')(self, key, $v = $x);
        }
        multi method ASSIGN-KEY(::?CLASS:D: \key, TValue \assignval) {
            my Mu $storage := nqp::getattr(self, EnumMap, '$!storage');
            $storage := nqp::bindattr(self, EnumMap, '$!storage', nqp::hash())
                unless nqp::defined($storage);
            my str $key = nqp::istype(key, Str) ?? key !! key.Str;
            if nqp::existskey($storage, $key) {
                nqp::atkey($storage, $key) = assignval;
            }
            else {
                nqp::bindkey($storage, $key,
                    nqp::p6scalarfromdesc(nqp::getattr(self, Hash, '$!descriptor')) = assignval)
            }
        }
        method BIND-KEY($key, TValue \bindval) is rw {
            nqp::defined(nqp::getattr(self, EnumMap, '$!storage')) ||
                nqp::bindattr(self, EnumMap, '$!storage', nqp::hash());
            nqp::bindkey(
                nqp::getattr(self, EnumMap, '$!storage'),
                nqp::unbox_s($key.Str),
                bindval)
        }
        multi method perl(::?CLASS:D \SELF:) {
            if not %*perlseen<TOP> { my %*perlseen = :TOP ; return self.perl }
            if %*perlseen{self.WHICH} { %*perlseen{self.WHICH} = 2; return "Hash_{self.WHERE}" }
            %*perlseen{self.WHICH} = 1;
            my $result = '(my '
              ~ TValue.perl
              ~ ' % = '
              ~ self.pairs.sort.map({.perl}).join(', ')
              ~ ')';
            $result = "(my \\Hash_{self.WHERE} = $result)" if %*perlseen{self.WHICH}:delete == 2;
            $result;
        }
    }
    my role TypedHash[::TValue, ::TKey] does Associative[TValue] {
        has $!keys;
        method keyof () { TKey }
        method AT-KEY(::?CLASS:D: TKey \key) is rw {
            my $key_which = key.WHICH;
            if self.EXISTS-KEY(key) {
                nqp::findmethod(EnumMap, 'AT-KEY')(self, $key_which);
            }
            else {
                nqp::p6bindattrinvres(
                    (my \v := nqp::p6scalarfromdesc(nqp::getattr(self, Hash, '$!descriptor'))),
                    Scalar,
                    '$!whence',
                    -> {
                        nqp::defined(nqp::getattr(self, $?CLASS, '$!keys')) ||
                            nqp::bindattr(self, $?CLASS, '$!keys', nqp::hash());
                        nqp::defined(nqp::getattr(self, EnumMap, '$!storage')) ||
                            nqp::bindattr(self, EnumMap, '$!storage', nqp::hash());
                        nqp::bindkey(
                            nqp::getattr(self, $?CLASS, '$!keys'),
                            nqp::unbox_s($key_which),
                            key);
                        nqp::bindkey(
                            nqp::getattr(self, EnumMap, '$!storage'),
                            nqp::unbox_s($key_which),
                            v);
                    });
            }
        }
        method STORE_AT_KEY(TKey \key, TValue $x) is rw {
            my $key_which = key.WHICH;
            nqp::defined(nqp::getattr(self, $?CLASS, '$!keys')) ||
                nqp::bindattr(self, $?CLASS, '$!keys', nqp::hash());
            nqp::defined(nqp::getattr(self, EnumMap, '$!storage')) ||
                nqp::bindattr(self, EnumMap, '$!storage', nqp::hash());
            nqp::bindkey(
                nqp::getattr(self, $?CLASS, '$!keys'),
                nqp::unbox_s($key_which),
                key);
            my $v :=
              nqp::p6scalarfromdesc(nqp::getattr(self, Hash, '$!descriptor'));
            nqp::bindkey(
                nqp::getattr(self, EnumMap, '$!storage'),
                nqp::unbox_s($key_which),
                $v = $x);
        }
        method ASSIGN-KEY(::?CLASS:D: TKey \key, TValue \assignval) {
            my Mu $storage := nqp::getattr(self, EnumMap, '$!storage');
            $storage := nqp::bindattr(self, EnumMap, '$!storage', nqp::hash())
                unless nqp::defined($storage);
            my str $key_which = nqp::unbox_s(key.WHICH);
            if nqp::existskey($storage, $key_which) {
                nqp::atkey($storage, $key_which) = assignval;
            }
            else {
                nqp::defined(nqp::getattr(self, $?CLASS, '$!keys')) ||
                    nqp::bindattr(self, $?CLASS, '$!keys', nqp::hash());
                nqp::bindkey(nqp::getattr(self, $?CLASS, '$!keys'), $key_which, key);
                nqp::bindkey($storage, $key_which,
                    nqp::p6scalarfromdesc(nqp::getattr(self, Hash, '$!descriptor')) = assignval)
            }
        }
        method BIND-KEY(TKey \key, TValue \bindval) is rw {
            my $key_which = key.WHICH;
            nqp::defined(nqp::getattr(self, $?CLASS, '$!keys')) ||
                nqp::bindattr(self, $?CLASS, '$!keys', nqp::hash());
            nqp::defined(nqp::getattr(self, EnumMap, '$!storage')) ||
                nqp::bindattr(self, EnumMap, '$!storage', nqp::hash());
            nqp::bindkey(
                nqp::getattr(self, $?CLASS, '$!keys'),
                nqp::unbox_s($key_which),
                key);
            nqp::bindkey(
                nqp::getattr(self, EnumMap, '$!storage'),
                nqp::unbox_s($key_which),
                bindval)
        }
        method EXISTS-KEY(TKey \key) {
            nqp::defined($!keys)
              ?? nqp::p6bool(nqp::existskey($!keys, nqp::unbox_s(key.WHICH)))
              !! False
        }
        method keys(EnumMap:) {
            return ().list unless self.DEFINITE && nqp::defined($!keys);
            Seq.new(class :: does Iterator {
                has $!hash-iter;

                method new(\hash, $class) {
                    my \iter = self.CREATE;
                    nqp::bindattr(iter, self, '$!hash-iter',
                        nqp::iterator(nqp::getattr(hash, $class, '$!keys')));
                    iter
                }

                method pull-one() {
                    $!hash-iter
                        ?? nqp::iterval(nqp::shift($!hash-iter))
                        !! IterationEnd
                }
            }.new(self, $?CLASS))
        }
        method kv(EnumMap:) {
            return ().list unless self.DEFINITE && nqp::defined($!keys);

            my $storage := nqp::getattr(self, EnumMap, '$!storage');
            Seq.new(class :: does Iterator {
                has $!hash-iter;
                has $!storage;
                has int $!on-value;
                has $!current-value;

                method new(\hash, $class, $storage) {
                    my \iter = self.CREATE;
                    nqp::bindattr(iter, self, '$!hash-iter',
                        nqp::iterator(nqp::getattr(hash, $class, '$!keys')));
                    nqp::bindattr(iter, self, '$!storage', nqp::decont($storage));
                    iter
                }

                method pull-one() {
                    if $!hash-iter {
                    }
                    if $!on-value {
                        $!on-value = 0;
                        $!current-value
                    }
                    elsif $!hash-iter {
                        my \tmp = nqp::shift($!hash-iter);
                        $!on-value = 1;
                        $!current-value := nqp::atkey($!storage, nqp::iterkey_s(tmp));
                        nqp::iterval(tmp)
                    }
                    else {
                        IterationEnd
                    }
                }
            }.new(self, $?CLASS, nqp::getattr(self, EnumMap, '$!storage')))
        }
        method pairs(EnumMap:) {
            return ().list unless self.DEFINITE && nqp::defined($!keys);

            my $storage := nqp::getattr(self, EnumMap, '$!storage');
            Seq.new(class :: does Iterator {
                has $!hash-iter;
                has $!storage;

                method new(\hash, $class, $storage) {
                    my \iter = self.CREATE;
                    nqp::bindattr(iter, self, '$!hash-iter',
                        nqp::iterator(nqp::getattr(hash, $class, '$!keys')));
                    nqp::bindattr(iter, self, '$!storage', nqp::decont($storage));
                    iter
                }

                method pull-one() {
                    if $!hash-iter {
                        my \tmp = nqp::shift($!hash-iter);
                        Pair.new(key => nqp::iterval(tmp), value => nqp::atkey($!storage, nqp::iterkey_s(tmp)));
                    }
                    else {
                        IterationEnd
                    }
                }
            }.new(self, $?CLASS, nqp::getattr(self, EnumMap, '$!storage')))
        }
        method antipairs(EnumMap:) {
            self.map: { .value => .key }
        }
        method invert(EnumMap:) {
            self.map: { .value »=>» .key }
        }
        multi method perl(::?CLASS:D \SELF:) {
            if not %*perlseen<TOP> { my %*perlseen = :TOP ; return self.perl }
            if %*perlseen{self.WHICH} { %*perlseen{self.WHICH} = 2; return "Hash_{self.WHERE}" }
            %*perlseen{self.WHICH} = 1;
            my $result;

            my $TKey-perl   := TKey.perl;
            my $TValue-perl := TValue.perl;
            if $TKey-perl eq 'Any' && $TValue-perl eq 'Mu' {
                $result = ':{' ~ SELF.pairs.sort.map({.perl}).join(', ') ~ '}'
            }
            else {
                $result = "(my $TValue-perl %\{$TKey-perl\} = {
                  self.pairs.sort.map({.perl}).join(', ')
                })";
            }

            $result = "(my \\Hash_{self.WHERE} = $result)" if %*perlseen{self.WHICH}:delete == 2;
            $result;
        }
        multi method DELETE-KEY($key) {
            my Mu $val = self.AT-KEY($key);
            my $key-which = $key.WHICH;

            nqp::deletekey(
                nqp::getattr(self, $?CLASS, '$!keys'),
                nqp::unbox_s($key-which)
            );

            nqp::deletekey(
                nqp::getattr(self, EnumMap, '$!storage'),
                nqp::unbox_s($key-which)
            );
            $val;
        }

        # gotta force capture keys to strings or binder fails
        method Capture(EnumMap:D:) {
            my $cap := nqp::create(Capture);
            my $h := nqp::hash();
            for self.kv -> \k, \v {
                my str $skey = nqp::istype(k, Str) ?? k !! k.Str;
                nqp::bindkey($h, $skey, v);
            }
            nqp::bindattr($cap, Capture, '$!hash', $h);
            $cap
        }

    }
    method ^parameterize(Mu:U \hash, Mu:U \t, |c) {
        if c.elems == 0 {
            my $what := hash.^mixin(TypedHash[t]);
            # needs to be done in COMPOSE phaser when that works
            $what.^set_name("{hash.^name}[{t.^name}]");
            $what;
        }
        elsif c.elems == 1 {
            my $what := hash.^mixin(TypedHash[t, c[0].WHAT]);
            # needs to be done in COMPOSE phaser when that works
            $what.^set_name("{hash.^name}[{t.^name},{c[0].^name}]");
            $what;
        }
        else {
            die "Can only type-constrain Hash with [ValueType] or [ValueType,KeyType]";
        }
    }
}


sub circumfix:<{ }>(*@elems) { my % = @elems }
sub hash(*@a, *%h) { my % = flat @a, %h }

# XXX parse hangs with ordinary sub declaration
BEGIN my &circumfix:<:{ }> = sub (*@elems) { Hash.^parameterize(Mu,Any).new(@elems) }

# vim: ft=perl6 expandtab sw=4

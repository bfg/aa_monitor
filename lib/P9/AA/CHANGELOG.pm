=head1 NAME

aa_monitor changelog

=head1 VERSIONS

=head2 1.0.5

=over

=item * new module: L<B<Mount>|P9::AA::Check::Mount> - check if all filesystems are mounted

=item * module L<B<FSUsage>|P9::AA::Check::FSUsage> - device names are not unique, code refactoring

=item * Daemon: really respect max_clients = 0

=item * HTML output renderer: Added readme, changelog and module POD hyperlinks to HTML output if enable_doc == true

=item * modules L<B<Time>|P9::AA::Check::Time>, L<B<Process>|P9::AA::Check::Process>: added toString() check description method.

=back

=head2 1.0.4

=over

=item * Daemon: B<max_clients = 0> disables max_clients limit, removed _cleanupStaleKids() checks
because it crashes perl <= 5.8.8 interpreter. 

=back

=head2 1.0.3

=over

=item * added CHANGELOG pod

=item * module: finished L<B<MongoDB>|P9::AA::Check::MongoDB>.

=item * module: finished L<B<MongoDBReplicaSet>|P9::AA::Check::MongoDBReplicaSet>.

=item * module L<B<DBIReplication>|P9::AA::Check::DBIReplication>:
Fixed minor typo that caused check to fail.

=item * config: added configuration parameter B<max_execution_time>

=item * basic daemon implementation

=over

=item * check for zombie kids (respect max_execution_time) before each accept()

=item * report what's going on in SIGCHLD handler in debug mode

=item * reconfigure logger on SIGHUP

=back

=back

=head2 1.0.2

=over

=item * bundled module L<Net::INET6Glue>

=item * Debian package fixes.

=back

=cut
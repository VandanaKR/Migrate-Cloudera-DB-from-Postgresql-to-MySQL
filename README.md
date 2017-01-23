# Migrate-Cloudera-DB-from-Postgresql-to-MySQL
A script to migrate Cloudera manager server database from Embedded Postgresql to MySQL
While building up a cloudera distributed hadoop cluster,  cloudera automatically takes its own embedded postgresql DB as its server database, if no other external database were provided. But according to cloudera's best practices, it is adviced to have MySQL as cloudera server database and so they recommend to migrate if cluster is build on embedded postgresql. 
This script take care of all the backend manual process to be performed for the cloudera DB migration, except the single click starting and stopping of the services via Cloudera manager UI.

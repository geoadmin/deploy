database managment scripts
==========================
These scripts have been developped for the database and table duplication on a debian instance with postgresql-client package installed.
The scripts have to be executed with ``geodata`` user. To become geodata you have to type:
```bash
$ sudo su - geodata
```
## Installation
Clone the git repository to geodata's home:
```bash
$ git clone git@github.com:geoadmin/deploy.git
$ cd deploy/db_master_deploy/
```
Make sure that geodata .pgpass file exists. It should contain the credentials for db superuser.

The script output will be written to syslog ``/var/log/messages`` and can be analyzed with kibana interface.

### database naming convention and service address
The read-only hot-standby slaves can be accessed via this hostname: ``pg.bgdi.ch``
Each database has to have one of the following suffixes

DB Suffix    | Meaning
-------------|------------|
**_master** |  Original database, will be continuosly updated, should not be used in any applications |
**_dev**   | read-only development copy of _master database  | 
**_int**   | read-only integration copy of _master database | 
**_prod**  | read-only production copy of _master database  | 
**_``[a-zA-Z0-9]``+** | timestamped copy of _master database (bod only, use parameter -a [a-zA-Z0-9]+ for the archive suffix) |

### copy databases and or tables (deploy.sh)
You can copy a comma delimited list of tables and/or database to one target. 
The following targets can be used ``dev int prod``. 
Normally we are deploying from a _master datasource to one of these targets. If you choose another source, the script will ask you for confirmation.
Table copy is performance optimized sql copy from stdout to stdin. 
The job will be using all the available cores by splitting up the table into  parts with equal number of rows, indexes and constraints will be removed before writing the table and re-created afterwards.

In the deploy script examples below we're always using the _master as source database. The deploy chain should be:
```bash
_master -> _dev
_dev -> _int
_int -> _prod
```

Depending on the composition of the source_object parameter and the other parameters the script can be executed in the following modes:

#### table-copy
```bash
$ bash deploy.sh -s stopo_dev.tlm.strasse -t int
```
```bash
$ bash deploy.sh -s stopo_master.public.grid_ta25,bafu_master.prtr.swissprtr -t dev
```
The script fires the sphinx trigger script dml_trigger.sh

Database copy is is an optimized version of ``createdb -T source_db``.

#### database-copy 
Deploy bod from dev to integration:
```bash
$ bash deploy.sh -s bod_dev -t int
```
Deploy bod from integration to production and make an archive copy, the script will create a new database named: ``bod_master20150315``
```
$ bash deploy.sh -s bod_int -t prod -a 20150315
```
Deploy bafu and stopo from integration to production
```bash
$ bash deploy.sh -s stopo_int,bafu_int -t prod
```

#### mixed copy database/table
Deploy bod to integration:
```bash
$ bash deploy.sh -s bod_dev,stopo_dev.tlm.strasse -t int
```

#### materialized views
materialized views are updated by default during:
* full database deploy - before the deploy begins in the source database
* table deploy - after the deploy in the target database
* table deploy - in the source database if the deploy is from `master` to `dev`

for the table deploy, only the materialized views which rely on the deployed tables will be updated.

you can deactivate the materialized view update with the optional parameter ``-r false``  

```bash
$ bash deploy.sh -s stopo_dev.tlm.strasse -t int -r false
```

#### bod archive
Create an archive/snapshot of the BOD:
```bash
bash deploy.sh -s bod_master -a 20150301
```
This command will create a snapshot of ``bod_master -> bod_master20150301``. 
There are no triggers fired.

The deploy.sh script fires the sphinx trigger script dml_trigger.sh for table and database copies.

The deploy.sh script fires the github trigger script ddl_trigger.sh for database copies only.

### default data deploy worklow
```
          +--------------+                                                                                    
          |              |                                                                                    
          |              |                                                                                    
          |              |                                                                                    
          |    _prod     | <---+                                                                              
          |              |     |                                                                              
          |              |     |           +-----------------------------------------------------------------+
          |              |     |           | Default database deploy workflow                                |
          +--------------+     |           |                                                                 |
                               C           | A: deploy from master to dev                                    |
          +--------------+     |           |    bash deploy.sh -s bod_master,stopo_master.tlm.strasse -t dev |
          |              |     |           |                                                                 |
          |              |     |           |                                                                 |
          |              |     |           | B: deploy from dev to int                                       |
+-------> |    _int      +-----+           |    bash deploy.sh -s bod_dev,stopo_dev.tlm.strasse -t int       |
|         |              |                 |                                                                 |
|         |              |                 |                                                                 |
|         |              |                 | C: deploy from int to prod                                      |
B         +--------------+                 |     bash deploy.sh -s bod_int,stopo_int.tlm.strasse -t prod     |
|                                          |                                                                 |
|         +--------------+                 +-----------------------------------------------------------------+
|         |              |                                                                                    
+----+----+              |                                                                                    
          |              |                                                                                    
     +--> |    _dev      |                                                                                    
     |    |              |                                                                                    
     |    |              |                                                                                    
     |    |              |                                                                                    
     |    +--------------+                                                                                    
     A                                                                                                        
     |                                                                                                        
     |    +--------------+                                                                                    
     |    |              |                                                                                    
     |    |              |                                                                                    
     |    |              |                                                                                    
     +----+   _master    |                                                                                    
          |              |                                                                                    
          |              |                                                                                    
          |              |                                                                                    
          +--------------+                                                                                    
```
* This is the default workflow for data updates. It should be bypassed only in exceptional circumstances. 
* New data will always be created on _master databases. The other databases are read-only. 
* every deploy to prod has to be deployed to int first. It should always be in "pre-production" state.

### dml trigger (dml_trigger.sh)
**SPHINX Index**: 
updating the sphinx indexes can be triggered with the optional parameter ``-d {true|false}``, default is ``true`` which means that the sphinx indexes will be updated.

### ddl trigger (ddl_trigger.sh)
Update DDL dump Repository in Github https://github.com/geoadmin/db

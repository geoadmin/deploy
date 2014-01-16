#!/bin/bash

# This script does the following
# - update project from repository
# - build the project (dev configuration)
# - create a snapshot
# - deploy this snapshot to integration
# - create script to deploy this snapshot to integration (for repeated task)
# - create script to deploy this snapshot to production

PRODFILE=`pwd`/bazl2prod.sh
INTWITHSNAPFILE=`pwd`/bazl2integrationwithsnapshot.sh
PROJECTPATH=/var/www/vhosts/mf-bazl/private/bazl/
SNAPSHOTPATH=/var/www/vhosts/mf-bazl/private/snapshots/`date '+%Y%m%d%H%M'`

#build latest version
cd $PROJECTPATH
svn up
buildout/bin/buildout -c buildout_dev.cfg

#create snapshot
sudo -u deploy deploy -c deploy/deploy.cfg $SNAPSHOTPATH

#deploy this snapshot to integration
sudo -u deploy deploy -r deploy/deploy.cfg int $SNAPSHOTPATH

#create integration deploy script with this snapshot
echo "#!/bin/bash" > $INTWITHSNAPFILE
echo "cd " $PROJECTPATH >> $INTWITHSNAPFILE
echo "sudo -u deploy deploy -r deploy/deploy.cfg int "$SNAPSHOTPATH >> $INTWITHSNAPFILE
chmod 777 $INTWITHSNAPFILE
echo $INTWITHSNAPFILE " created."

#create production deploy script with this snapshot
echo "#!/bin/bash" > $PRODFILE
echo "cd " $PROJECTPATH >> $PRODFILE
echo "sudo -u deploy deploy -r deploy/deploy.cfg prod "$SNAPSHOTPATH >> $PRODFILE
chmod 777 $PRODFILE
echo $PRODFILE " created."


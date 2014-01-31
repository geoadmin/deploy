Bascic principles of these scripts
=================================

When running each of these scripts, the following is done:

- Checkout newest version from code repository (trunk/master) into /var/www/vhosts/....
- Build for 'dev'
- Create a snapshot of the build
- Deploy the snapshot to integration
- Create a script that will deploy the project to integration with the snapshot created in step 3 (*withsnapshot.sh)
- Create a script that will deploy the project to production with the snapshot created in step 3 (*prod.sh)

To (re)deploy the same snapshot to integration or production, you can use the
scripts created by the above process.


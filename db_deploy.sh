#!bin/bash
targets="db_cluster_t db_cluster_i db_cluster_p"
targets="db_cluster_p"
targets="db_cluster_t"

for target in $targets
do  
    # stopo
    sudo -u deploy deploy -r --tables=stopo.public.vec200_access /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_airport /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_building /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_builtupp /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_com_boundary /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_commune /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_customsoffice /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_dam /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_flowingwater /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_geodpoint /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_gwk_fw_node /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_hydroinfo /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_interchange /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_junctions /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_lake /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_landcover /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_namedlocation /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_poi /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_protectedarea /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_railway /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_ramp /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_road /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_runway /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_ship /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_stagnantwater /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_supply /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_terminal /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_trafficinfo /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.public.vec200_physl /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.tlm.prodas_spatialseltype_gemeinde_multilingual /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.tlm.prodas_spatialseltype_bezirk /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.tlm.prodas_spatialseltype_kanton /home/deploy/deploy-database/deploy.cfg $target
    sudo -u deploy deploy -r --tables=stopo.vd.gabmo_plz /home/deploy/deploy-database/deploy.cfg $target
    # kogis
    sudo -u deploy deploy -r --tables=kogis.bfs.adr /home/deploy/deploy-database/deploy.cfg $target
    # lubis
    sudo -u deploy deploy -r --tables=lubis /home/deploy/deploy-database/deploy.cfg $target
    # bod
    sudo -u deploy deploy -r --tables=bod /home/deploy/deploy-database/deploy.cfg $target
done

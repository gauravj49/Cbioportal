# Step 1 - Setup network
# Create a network in order for the cBioPortal container and mysql database to communicate.
sudo docker network create cbio-net

# Remove already existing docker
# docker ps -a
# docker rm <name of the  docker>

# Step 2 - Run mysql with seed database
# Start a MySQL server. The command below stores the database in a folder named /<path_to_save_mysql_db>/db_files/. This should be an absolute path.
sudo docker run -d --restart=always \
  --name=cbioDB \
  --net=cbio-net \
  -e MYSQL_ROOT_PASSWORD='P@ssword1' \
  -e MYSQL_USER=cbio \
  -e MYSQL_PASSWORD='P@ssword1' \
  -e MYSQL_DATABASE=cbioportal \
  -v /home/gjain/bin/projects/Cbioportal/input/setup/mysqldb/db_files/:/var/lib/mysql/ \
  mysql:5.7

# Create the cBioPortal MySQL Databases and User
# You must create a cbioportal database and a cgds_test database within MySQL, and a user account with rights to access both databases. This is done via the mysql shell.

    # > sudo mysql -u root -p
    # Enter password: ********

    # Welcome to the MySQL monitor.  Commands end with ; or \g.
    # Your MySQL connection id is 64
    # Server version: 5.6.23 MySQL Community Server (GPL)

    # Copyright (c) 2000, 2015, Oracle and/or its affiliates. All rights reserved.

    # mysql> create database cbioportal;
    # Query OK, 1 row affected (0.00 sec)

    # mysql> create database cgds_test;
    # Query OK, 1 row affected (0.00 sec)

    # mysql> CREATE USER 'cbio_user'@'localhost' IDENTIFIED BY 'cbio_user9';
    # Query OK, 0 rows affected (0.00 sec)

    # mysql> GRANT ALL ON cbioportal.* TO 'cbio_user'@'localhost';
    # Query OK, 0 rows affected (0.00 sec)

    # mysql> GRANT ALL ON cgds_test.* TO 'cbio_user'@'localhost';
    # Query OK, 0 rows affected (0.00 sec)

    # mysql>  flush privileges;
    # Query OK, 0 rows affected (0.00 sec)

# Import the cBioPortal Seed Database
mysql --user=cbio_user --password=cbio_user9 cbioportal < scripts/cbioportal/db-scripts/src/main/resources/cgds.sql
mysql --user=cbio_user --password=cbio_user9 cbioportal < input/setup/seedDB/seed-cbioportal_hg19_v2.7.3.sql


# If the user has rights to all available cancer studies, a single entry with the keyword app.name: + "ALL" is sufficient (so e.g. "cbioportal:ALL").
# You need to add users via MySQL directly. For example:
# mysql> INSERT INTO cbioportal.authorities (EMAIL, AUTHORITY) VALUES ('john.smith@gmail.com', 'cbioportal:CANCER_STUDY_1');
INSERT INTO cbioportal.authorities (EMAIL, AUTHORITY) VALUES ('gaurav.jain@tum.de', 'cbioportal:CANCER_STUDY_1');
    
# Download the seed database from the cBioPortal Datahub, and use the command below to upload the seed data to the server started above.
# Make sure to replace /<path_to_seed_database>/seed-cbioportal_<genome_build>_<seed_version>.sql.gz with the path and name of the downloaded seed database. Again, this should be an absolute path.
sudo docker run --name=load-seeddb --net=cbio-net -e MYSQL_USER=cbio -e MYSQL_PASSWORD='P@ssword1' \
  -v /home/gjain/bin/projects/Cbioportal/input/setup/seedDB/cgds.sql:/mnt/cgds.sql:ro \
  -v /home/gjain/bin/projects/Cbioportal/input/setup/seedDB/seed-cbioportal_hg19_v2.7.3.sql.gz:/mnt/seed.sql.gz:ro \
  mysql:5.7 \
  sh -c 'cat /mnt/cgds.sql | mysql -hcbioDB -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" cbioportal \
      && zcat /mnt/seed.sql.gz |  mysql -hcbioDB -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" cbioportal'

# Follow the logs of this step to ensure that no errors occur. If any error occurs, make sure to check it. A common cause is pointing the -v parameters above to folders or files that do not exist.
# Note that another option would be to use an external database. In that case one does not need to run the cbioDB container. In the command for the load-seeddb change the cbioDB host to the host of the external MySQL database.

# Step 3 - Set up a portal.properties file
# Copy the portal.properties.EXAMPLE and change it according to your wishes. See the full reference and the skin properties for more information on the relevant properties.
# Make sure to at least provide the database parameters from step 1, which are required for the next step:
db.user=cbio
db.password=P@ssword1
db.host=cbioDB
db.portal_db_name=cbioportal
db.connection_string=jdbc:mysql://cbioDB/

# If you are using an external database change the cbioDB hostname to the hostname of the MySQL database. If it requires an SSL connection use:
# db.use_ssl=true

# Step 4 - Migrate database to latest version
# Update the seeded database schema to match the cBioPortal version in the image, by running the following command. Note that this will most likely make your database irreversibly incompatible with older versions of the portal code.
sudo docker run --rm -it --net cbio-net \
    -v /home/gjain/bin/projects/Cbioportal/input/setup/config/portal.properties:/cbioportal/portal.properties:ro \
    cbioportal/cbioportal:3.0.1 \
    migrate_db.py -p /cbioportal/portal.properties -s /cbioportal/db-scripts/src/main/resources/migration.sql

# Step 5 - Run Session Service containers
# First, create the mongoDB database:
sudo docker run -d --name=mongoDB --net=cbio-net \
    -e MONGO_INITDB_DATABASE=session_service \
    mongo:3.6.6

# Finally, create a container for the Session Service, adding the link to the mongoDB database using -Dspring.data.mongodb.uri:
sudo docker run -d --name=cbio-session-service --net=cbio-net \
    -e SERVER_PORT=5000 \
    -e JAVA_OPTS="-Dspring.data.mongodb.uri=mongodb://mongoDB:27017/session-service" \
    cbioportal/session-service:latest

# Step 6 - Run the cBioPortal web server
# Add any cBioPortal configuration in portal.properties as appropriate—see the documentation on the main properties and the skin properties. Then start the web server as follows.
sudo docker run -d --restart=always \
    --name=cbioportal-container \
    --net=cbio-net \
    -v /<path_to_config_file>/portal.properties:/cbioportal/portal.properties:ro \
    -e JAVA_OPTS='
        -Xms2g
        -Xmx4g
        -Dauthenticate=noauthsessionservice
        -Dsession.service.url=http://cbio-session-service:5000/api/sessions/my_portal/
    ' \
    -p 8081:8080 \
    cbioportal/cbioportal:3.0.1 \
    /bin/sh -c 'java ${JAVA_OPTS} -jar webapp-runner.jar /cbioportal-webapp'

# To read more about the various ways to use authentication and webapp-runner see the relevant backend deployment documentation.
# On server systems that can easily spare 4 GiB or more of memory, set the -Xms and -Xmx options to the same number. This should increase performance of certain memory-intensive web services such as computing the data for the co-expression tab. If you are using MacOS or Windows, make sure to take a look at these notes to allocate more memory for the virtual machine in which all Docker processes are running.
# cBioPortal can now be reached at http://localhost:8081/
# Activity of Docker containers can be seen with:
docker ps -a
# Wordpress 101

## deployment
    - terraform init
    - terrafomr plan
    - terraform apply



## Worth Noting

After deployment, there will be an issue with starting up wordpress because of db connection. This is because by default the mysql flexible server requires connection to be secure. To overcome this, you will need to follow the following steps :

Go to mysql instance --> Server parameters (under Settings on the left pane) --> search for `require_secure_transport` --> set it to off and save your changes
 

# Testing

Get the public IP of Appliction Gateway and paste in the browser. For the purpose of this assessment, SSL certificates and custom domains for app services have been skipped. Traffic will be over http.


## Architecture

Attached is an architecture diagram that was followed to solution as a solution
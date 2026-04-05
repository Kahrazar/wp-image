# Comandos para subir 
aws ecr create-repository --repository-name wp-allinone --region us-east-1

docker build -t wp-allinone .

docker tag wp-allinone:latest 683808146566.dkr.ecr.us-east-1.amazonaws.com/wp-allinone:latest

# Construir imagen sin Cache
docker build --no-cache -t wp-allinone . 


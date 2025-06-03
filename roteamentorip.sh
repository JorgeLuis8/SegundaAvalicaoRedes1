#!/bin/bash

# Passo 1: Criar as Redes Docker
echo "### Passo 1: Criando as Redes Docker ###"
# Remover redes existentes (se houver)
docker network rm lan1 lan2 lan3 lan4 2>/dev/null || true

# Criar as 4 redes (LANs)
docker network create --driver bridge --subnet=192.168.1.0/24 lan1
docker network create --driver bridge --subnet=192.168.2.0/24 lan2
docker network create --driver bridge --subnet=192.168.3.0/24 lan3
docker network create --driver bridge --subnet=192.168.4.0/24 lan4
echo "Redes Docker criadas."
echo ""

# Passo 3: Criar os Containers dos Roteadores
echo "### Passo 3: Criando os Containers dos Roteadores ###"
docker run -d --name roteador1 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.1.10 ubuntu:latest sleep infinity
docker run -d --name roteador2 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.1.20 ubuntu:latest sleep infinity
docker run -d --name roteador3 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.1.30 ubuntu:latest sleep infinity
echo "Containers dos roteadores criados."
echo ""

# Passo 4: Conectar Roteadores às Redes Adicionais
echo "### Passo 4: Conectando Roteadores às Redes Adicionais ###"
docker network connect --ip 192.168.2.20 lan2 roteador2 # eth1 em roteador2
docker network connect --ip 192.168.3.20 lan3 roteador2 # eth2 em roteador2
docker network connect --ip 192.168.3.30 lan3 roteador3 # eth1 em roteador3
docker network connect --ip 192.168.4.30 lan4 roteador3 # eth2 em roteador3
echo "Roteadores conectados às redes adicionais."
echo ""

# Passo 5: Criar os Hosts
echo "### Passo 5: Criando os Hosts ###"
docker run -d --name host-lan2 --privileged --cap-add=NET_ADMIN --net lan2 --ip 192.168.2.100 ubuntu:latest sleep infinity
docker run -d --name host-lan3 --privileged --cap-add=NET_ADMIN --net lan3 --ip 192.168.3.100 ubuntu:latest sleep infinity
docker run -d --name host-lan4 --privileged --cap-add=NET_ADMIN --net lan4 --ip 192.168.4.100 ubuntu:latest sleep infinity
echo "Containers dos hosts criados."
echo ""

# Passo 6: Criar os Servidores Web com Mapeamento de Portas
echo "### Passo 6: Criando os Servidores Web ###"
docker run -d --name webserver-lan2 --privileged --cap-add=NET_ADMIN --net lan2 --ip 192.168.2.200 -p 8081:80 nginx:latest
docker run -d --name webserver-lan3 --privileged --cap-add=NET_ADMIN --net lan3 --ip 192.168.3.200 -p 8082:80 nginx:latest
docker run -d --name webserver-lan4 --privileged --cap-add=NET_ADMIN --net lan4 --ip 192.168.4.200 -p 8083:80 nginx:latest
echo "Containers dos servidores web criados."
echo ""

echo "Aguardando containers iniciarem (15 segundos)..."
sleep 15

# Passo 7: Instalar Ferramentas em Todos os Containers
echo "### Passo 7: Instalando Ferramentas nos Containers ###"
ROUTERS="roteador1 roteador2 roteador3"
for router in $ROUTERS; do
  echo "Instalando ferramentas e FRR no $router..."
  # Adicionar -y para apt-get install e garantir noninteractive para frr
  docker exec $router bash -c "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y iproute2 iputils-ping net-tools frr"
done

HOSTS="host-lan2 host-lan3 host-lan4"
for host in $HOSTS; do
  echo "Instalando ferramentas no $host..."
  docker exec $host bash -c "apt-get update && apt-get install -y iproute2 iputils-ping net-tools links"
done

WEBSERVERS="webserver-lan2 webserver-lan3 webserver-lan4"
for webserver in $WEBSERVERS; do
  echo "Instalando ferramentas no $webserver..."
  docker exec $webserver bash -c "apt-get update && apt-get install -y iproute2 iputils-ping net-tools"
done
echo "Ferramentas instaladas."
echo ""

# Passo 8: Habilitar IP Forwarding nos Roteadores
echo "### Passo 8: Habilitando IP Forwarding nos Roteadores ###"
for router in $ROUTERS; do
  docker exec $router bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
done
echo "IP Forwarding habilitado."
echo ""

# Passo 9: Configurar RIP com FRR nos Roteadores
echo "### Passo 9: Configurando RIP com FRR nos Roteadores ###"

FRR_DAEMONS_CONFIG='sed -i "s/zebra=no/zebra=yes/" /etc/frr/daemons && sed -i "s/ripd=no/ripd=yes/" /etc/frr/daemons'

# Configurar Roteador 1
echo "Configurando FRR no roteador1..."
docker exec roteador1 bash -c "$FRR_DAEMONS_CONFIG && \
cat > /etc/frr/frr.conf << EOF
frr defaults traditional
hostname roteador1
log syslog informational
!
router rip
 version 2
 network 192.168.1.0/24
 redistribute connected
!
line vty
!
EOF
service frr restart"

# Configurar Roteador 2
echo "Configurando FRR no roteador2..."
docker exec roteador2 bash -c "$FRR_DAEMONS_CONFIG && \
cat > /etc/frr/frr.conf << EOF
frr defaults traditional
hostname roteador2
log syslog informational
!
router rip
 version 2
 network 192.168.1.0/24
 network 192.168.2.0/24
 network 192.168.3.0/24
 redistribute connected
!
line vty
!
EOF
service frr restart"

# Configurar Roteador 3
echo "Configurando FRR no roteador3..."
docker exec roteador3 bash -c "$FRR_DAEMONS_CONFIG && \
cat > /etc/frr/frr.conf << EOF
frr defaults traditional
hostname roteador3
log syslog informational
!
router rip
 version 2
 network 192.168.1.0/24
 network 192.168.3.0/24
 network 192.168.4.0/24
 redistribute connected
!
line vty
!
EOF
service frr restart"

echo "Configuração RIP (FRR) concluída e serviços reiniciados."
echo "Aguardando convergência do RIP (20 segundos)..."
sleep 20 # Dar tempo para o RIP convergir
echo ""

# Passo 10: Configurar Gateway Padrão nos Hosts e Servidores
echo "### Passo 10: Configurando Gateway Padrão nos Hosts e Servidores ###"
docker exec host-lan2 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.2.20"
docker exec host-lan3 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.3.20"
docker exec host-lan4 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.4.30"

docker exec webserver-lan2 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.2.20"
docker exec webserver-lan3 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.3.20"
docker exec webserver-lan4 bash -c "ip route del default 2>/dev/null || true && ip route add default via 192.168.4.30"
echo "Gateway padrão configurado."
echo ""

# Passo 11: Criar Páginas Web Personalizadas
echo "### Passo 11: Criando Páginas Web Personalizadas ###"
# Site A (Portal Empresarial Alpha)
docker exec webserver-lan2 bash -c 'cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html><head><title>Portal Empresarial Alpha</title><style>body{font-family:Arial,sans-serif;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;text-align:center;padding:50px;margin:0}.container{max-width:600px;margin:0 auto;background:rgba(255,255,255,0.1);padding:40px;border-radius:15px;backdrop-filter:blur(10px);box-shadow:0 8px 32px rgba(0,0,0,0.3)}h1{color:#fff;font-size:2.5em;margin-bottom:20px}p{font-size:1.2em;margin:15px 0}.info{background:rgba(255,255,255,0.2);padding:15px;border-radius:10px;margin:20px 0}</style></head><body><div class="container"><h1>🌟 Portal Empresarial Alpha 🌟</h1><p>Bem-vindo ao nosso portal corporativo!</p><div class="info"><p><strong>Localização:</strong> Servidor na LAN2</p><p><strong>IP do Servidor:</strong> 192.168.2.200</p><p><strong>Domínio:</strong> www.alpha-empresa.com</p></div><p>Soluções empresariais de alta qualidade</p></div></body></html>
EOF'

# Site B (Centro de Inovação Beta)
docker exec webserver-lan3 bash -c 'cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html><head><title>Centro de Inovação Beta</title><style>body{font-family:Arial,sans-serif;background:linear-gradient(135deg,#f093fb 0%,#f5576c 100%);color:white;text-align:center;padding:50px;margin:0}.container{max-width:600px;margin:0 auto;background:rgba(255,255,255,0.1);padding:40px;border-radius:15px;backdrop-filter:blur(10px);box-shadow:0 8px 32px rgba(0,0,0,0.3)}h1{color:#fff;font-size:2.5em;margin-bottom:20px}p{font-size:1.2em;margin:15px 0}.info{background:rgba(255,255,255,0.2);padding:15px;border-radius:10px;margin:20px 0}</style></head><body><div class="container"><h1>🚀 Centro de Inovação Beta 🚀</h1><p>Hub de tecnologia e inovação!</p><div class="info"><p><strong>Localização:</strong> Servidor na LAN3</p><p><strong>IP do Servidor:</strong> 192.168.3.200</p><p><strong>Domínio:</strong> www.beta-inovacao.com</p></div><p>Desenvolvendo o futuro da tecnologia</p></div></body></html>
EOF'

# Site C (Hub Tecnológico Gamma)
docker exec webserver-lan4 bash -c 'cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html><head><title>Hub Tecnológico Gamma</title><style>body{font-family:Arial,sans-serif;background:linear-gradient(135deg,#4facfe 0%,#00f2fe 100%);color:white;text-align:center;padding:50px;margin:0}.container{max-width:600px;margin:0 auto;background:rgba(255,255,255,0.1);padding:40px;border-radius:15px;backdrop-filter:blur(10px);box-shadow:0 8px 32px rgba(0,0,0,0.3)}h1{color:#fff;font-size:2.5em;margin-bottom:20px}p{font-size:1.2em;margin:15px 0}.info{background:rgba(255,255,255,0.2);padding:15px;border-radius:10px;margin:20px 0}</style></head><body><div class="container"><h1>⚡ Hub Tecnológico Gamma ⚡</h1><p>Centro de excelência em tecnologia!</p><div class="info"><p><strong>Localização:</strong> Servidor na LAN4</p><p><strong>IP do Servidor:</strong> 192.168.4.200</p><p><strong>Domínio:</strong> www.gamma-tech.com</p></div><p>Transformando ideias em realidade digital</p></div></body></html>
EOF'
echo "Páginas web personalizadas criadas."
echo ""

# Passo 12: Configurar DNS/Hosts nos Containers
echo "### Passo 12: Configurando /etc/hosts nos Containers ###"
ETC_HOSTS_ENTRIES="192.168.2.200 www.alpha-empresa.com alpha-empresa.com sitea\n192.168.3.200 www.beta-inovacao.com beta-inovacao.com siteb\n192.168.4.200 www.gamma-tech.com gamma-tech.com sitec"

for container_name in host-lan2 host-lan3 host-lan4 roteador1 roteador2 roteador3; do
  echo -e "$ETC_HOSTS_ENTRIES" | docker exec -i $container_name bash -c "cat >> /etc/hosts"
done
echo "/etc/hosts configurado nos containers."
echo ""

# Passo 13: Configurar /etc/hosts na Máquina Host
echo "### Passo 13: Configurar /etc/hosts na Máquina Host ###"
echo "Lembre-se de configurar o arquivo hosts da sua máquina (C:\Windows\System32\drivers\etc\hosts no Windows ou /etc/hosts no Linux/macOS):"
echo "127.0.0.1 www.alpha-empresa.com"
echo "127.0.0.1 www.beta-inovacao.com"
echo "127.0.0.1 www.gamma-tech.com"
echo ""

# Passo 14: Testes de Conectividade
echo "### Passo 14: Testes de Conectividade (via RIP com FRR) ###"
echo "=== Teste de Conectividade entre Hosts ==="
docker exec host-lan2 ping -c 3 192.168.3.100
docker exec host-lan2 ping -c 3 192.168.4.100
docker exec host-lan3 ping -c 3 192.168.4.100
echo ""

echo "=== Teste de Acesso por IP ==="
docker exec host-lan2 links -dump http://192.168.2.200
docker exec host-lan2 links -dump http://192.168.3.200
docker exec host-lan2 links -dump http://192.168.4.200
echo ""

echo "=== Teste de Acesso por Domínio ==="
docker exec host-lan2 links -dump http://www.alpha-empresa.com
docker exec host-lan3 links -dump http://www.beta-inovacao.com
docker exec host-lan4 links -dump http://www.gamma-tech.com
echo ""

# Passo 15: Acesso da Máquina Host
echo "### Passo 15: Acesso da Máquina Host ###"
echo "Acesse os sites no seu navegador:"
echo "Site A: http://localhost:8081  OU  http://www.alpha-empresa.com:8081"
echo "Site B: http://localhost:8082  OU  http://www.beta-inovacao.com:8082"
echo "Site C: http://localhost:8083  OU  http://www.gamma-tech.com:8083"
echo ""

# Passo 16: Verificação Final
echo "### Passo 16: Verificação Final (RIP com FRR) ###"
echo "Verificar status dos containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "Verificar redes:"
docker network ls | grep lan
echo ""

echo "=== Rotas e Status RIP nos Roteadores (FRR) ==="
for router in $ROUTERS; do
  echo "--- $router (vtysh -c 'show ip route') ---"
  docker exec $router vtysh -c "show ip route"
  sleep 1
  echo "--- $router (vtysh -c 'show ip rip status') ---"
  docker exec $router vtysh -c "show ip rip status"
  sleep 1
  echo "--- $router (vtysh -c 'show ip rip') ---"
  docker exec $router vtysh -c "show ip rip" # Mostra rotas RIP e timers
  sleep 1
done
echo ""

echo "Configuração da topologia com RIP (FRR) concluída."
echo "Para limpar o ambiente, execute os comandos de limpeza no final do script."
echo ""

# Comandos de Limpeza (Se Necessário)
echo "### Comandos de Limpeza (Descomente para usar) ###"
echo "# Parar todos os containers"
echo "# docker stop \$(docker ps -q --filter \"name=roteador*\" --filter \"name=host-*\" --filter \"name=webserver-*\")"
echo ""
echo "# Remover todos os containers"
echo "# docker rm \$(docker ps -aq --filter \"name=roteador*\" --filter \"name=host-*\" --filter \"name=webserver-*\")"
echo ""
echo "# Remover todas as redes"
echo "# docker network rm lan1 lan2 lan3 lan4"
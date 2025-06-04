#!/bin/bash
set -e

echo "### Passo 1: Criar as Redes Docker ###"
echo "Removendo redes existentes (se houver)..."
docker network rm lan1 lan2 lan3 lan4 2>/dev/null || true

echo "Criando as 4 redes (LANs)..."
docker network create --driver bridge --subnet=192.168.1.0/24 lan1
docker network create --driver bridge --subnet=192.168.2.0/24 lan2
docker network create --driver bridge --subnet=192.168.3.0/24 lan3
docker network create --driver bridge --subnet=192.168.4.0/24 lan4
echo "Redes criadas."
echo "--------------------------------------------------"



echo "### Passo 3: Criar os Containers dos Roteadores ###"
echo "Criando roteador1..."
docker run -d --name roteador1 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.1.10 ubuntu:latest sleep infinity

echo "Criando roteador2..."
docker run -d --name roteador2 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.1.20 ubuntu:latest sleep infinity

echo "Criando roteador3..."
docker run -d --name roteador3 --privileged --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --net lan1 --ip 192.168.1.30 ubuntu:latest sleep infinity
echo "Containers dos roteadores criados."
echo "--------------------------------------------------"

echo "### Passo 4: Conectar Roteadores às Redes Adicionais ###"
echo "Conectando Roteador 2 às outras redes..."
docker network connect --ip 192.168.2.20 lan2 roteador2
docker network connect --ip 192.168.3.20 lan3 roteador2

echo "Conectando Roteador 3 às outras redes..."
docker network connect --ip 192.168.3.30 lan3 roteador3
docker network connect --ip 192.168.4.30 lan4 roteador3
echo "Roteadores conectados às redes adicionais."
echo "--------------------------------------------------"

echo "### Passo 5: Criar os Hosts ###"
echo "Criando host-lan2..."
docker run -d --name host-lan2 --privileged --cap-add=NET_ADMIN --net lan2 --ip 192.168.2.100 ubuntu:latest sleep infinity

echo "Criando host-lan3..."
docker run -d --name host-lan3 --privileged --cap-add=NET_ADMIN --net lan3 --ip 192.168.3.100 ubuntu:latest sleep infinity

echo "Criando host-lan4..."
docker run -d --name host-lan4 --privileged --cap-add=NET_ADMIN --net lan4 --ip 192.168.4.100 ubuntu:latest sleep infinity
echo "Hosts criados."
echo "--------------------------------------------------"

echo "### Passo 6: Criar os Servidores Web com Mapeamento de Portas ###"
echo "Criando webserver-lan2 (Site A) na porta 8081..."
docker run -d --name webserver-lan2 --privileged --cap-add=NET_ADMIN --net lan2 --ip 192.168.2.200 -p 8081:80 nginx:latest

echo "Criando webserver-lan3 (Site B) na porta 8082..."
docker run -d --name webserver-lan3 --privileged --cap-add=NET_ADMIN --net lan3 --ip 192.168.3.200 -p 8082:80 nginx:latest

echo "Criando webserver-lan4 (Site C) na porta 8083..."
docker run -d --name webserver-lan4 --privileged --cap-add=NET_ADMIN --net lan4 --ip 192.168.4.200 -p 8083:80 nginx:latest
echo "Servidores web criados."
echo "--------------------------------------------------"

echo "Aguardando containers inicializarem antes de instalar ferramentas (20 segundos)..."
sleep 20

echo "### Passo 7: Instalar Ferramentas em Todos os Containers ###"
echo "Instalando ferramentas nos roteadores..."
docker exec roteador1 bash -c "apt update && apt install -y iproute2 iputils-ping net-tools"
docker exec roteador2 bash -c "apt update && apt install -y iproute2 iputils-ping net-tools"
docker exec roteador3 bash -c "apt update && apt install -y iproute2 iputils-ping net-tools"

echo "Instalando ferramentas nos hosts..."
docker exec host-lan2 bash -c "apt update && apt install -y iproute2 iputils-ping net-tools links"
docker exec host-lan3 bash -c "apt update && apt install -y iproute2 iputils-ping net-tools links"
docker exec host-lan4 bash -c "apt update && apt install -y iproute2 iputils-ping net-tools links"

echo "Instalando ferramentas nos servidores web..."
docker exec webserver-lan2 bash -c "apt update && apt install -y iproute2 iputils-ping net-tools"
docker exec webserver-lan3 bash -c "apt update && apt install -y iproute2 iputils-ping net-tools"
docker exec webserver-lan4 bash -c "apt update && apt install -y iproute2 iputils-ping net-tools"
echo "Ferramentas instaladas."
echo "--------------------------------------------------"

echo "### Passo 8: Habilitar IP Forwarding nos Roteadores ###"
docker exec roteador1 bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
docker exec roteador2 bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
docker exec roteador3 bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
echo "IP Forwarding habilitado."
echo "--------------------------------------------------"

echo "### Passo 9: Configurar Rotas nos Roteadores ###"
echo "Configurando rotas no Roteador 1..."
docker exec roteador1 bash -c "ip route replace 192.168.2.0/24 via 192.168.1.20"
docker exec roteador1 bash -c "ip route replace 192.168.3.0/24 via 192.168.1.20"
docker exec roteador1 bash -c "ip route replace 192.168.4.0/24 via 192.168.1.30"

echo "Configurando rotas no Roteador 2..."
# R2 já conhece 192.168.1.0/24, 192.168.2.0/24, 192.168.3.0/24 (redes diretamente conectadas)
# Para alcançar LAN4 (192.168.4.0/24), R2 precisa enviar para R3 (192.168.1.30) que está na LAN1.
docker exec roteador2 bash -c "ip route replace 192.168.4.0/24 via 192.168.1.30"

echo "Configurando rotas no Roteador 3..."
# R3 já conhece 192.168.1.0/24, 192.168.3.0/24, 192.168.4.0/24
# Para alcançar LAN2 (192.168.2.0/24), R3 precisa enviar para R2 (192.168.1.20)
docker exec roteador3 bash -c "ip route replace 192.168.2.0/24 via 192.168.1.20"

echo "Rotas configuradas nos roteadores."
echo "--------------------------------------------------"



echo "### Passo 10: Configurar Gateway Padrão nos Hosts e Servidores ###"
echo "Configurando gateway em host-lan2..."
docker exec host-lan2 bash -c "ip route del default || true && ip route add default via 192.168.2.20"
echo "Configurando gateway em host-lan3..."
docker exec host-lan3 bash -c "ip route del default || true && ip route add default via 192.168.3.20" # Gateway é R2 na LAN3
echo "Configurando gateway em host-lan4..."
docker exec host-lan4 bash -c "ip route del default || true && ip route add default via 192.168.4.30"

echo "Configurando gateway em webserver-lan2..."
docker exec webserver-lan2 bash -c "ip route del default || true && ip route add default via 192.168.2.20"
echo "Configurando gateway em webserver-lan3..."
docker exec webserver-lan3 bash -c "ip route del default || true && ip route add default via 192.168.3.20" # Gateway é R2 na LAN3
echo "Configurando gateway em webserver-lan4..."
docker exec webserver-lan4 bash -c "ip route del default || true && ip route add default via 192.168.4.30"
echo "Gateways padrão configurados."
echo "--------------------------------------------------"

docker exec webserver-lan2 bash -c 'cat > /usr/share/nginx/html/index.html <<EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8" />
    <title>Portal Empresarial Alpha</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white; 
            text-align: center; 
            padding: 50px; 
            margin: 0;
        }
        .container { 
            max-width: 600px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 40px; 
            border-radius: 15px; 
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 { color: #fff; font-size: 2.5em; margin-bottom: 20px; }
        p { font-size: 1.2em; margin: 15px 0; }
        .info { background: rgba(255,255,255,0.2); padding: 15px; border-radius: 10px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌟 Portal Empresarial Alpha 🌟</h1>
        <p>Bem-vindo ao nosso portal corporativo!</p>
        <div class="info">
            <p><strong>Localização:</strong> Servidor na LAN2</p>
            <p><strong>IP do Servidor:</strong> 192.168.2.200</p>
            <p><strong>Domínio:</strong> www.alpha-empresa.com</p>
        </div>
        <p>Soluções empresariais de alta qualidade</p>
    </div>
</body>
</html>
EOF'


echo "Criando index.html para Centro de Inovação Beta (webserver-lan3)..."
docker exec webserver-lan3 bash -c 'cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8" />
    <title>Centro de Inovação Beta</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white; 
            text-align: center; 
            padding: 50px; 
            margin: 0;
        }
        .container { 
            max-width: 600px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 40px; 
            border-radius: 15px; 
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 { color: #fff; font-size: 2.5em; margin-bottom: 20px; }
        p { font-size: 1.2em; margin: 15px 0; }
        .info { background: rgba(255,255,255,0.2); padding: 15px; border-radius: 10px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Centro de Inovação Beta 🚀</h1>
        <p>Hub de tecnologia e inovação!</p>
        <div class="info">
            <p><strong>Localização:</strong> Servidor na LAN3</p>
            <p><strong>IP do Servidor:</strong> 192.168.3.200</p>
            <p><strong>Domínio:</strong> www.beta-inovacao.com</p>
        </div>
        <p>Desenvolvendo o futuro da tecnologia</p>
    </div>
</body>
</html>
EOF'

echo "Criando index.html para Hub Tecnológico Gamma (webserver-lan4)..."
docker exec webserver-lan4 bash -c 'cat > /usr/share/nginx/html/index.html << EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8" />
    <title>Hub Tecnológico Gamma</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
            color: white; 
            text-align: center; 
            padding: 50px; 
            margin: 0;
        }
        .container { 
            max-width: 600px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 40px; 
            border-radius: 15px; 
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        h1 { color: #fff; font-size: 2.5em; margin-bottom: 20px; }
        p { font-size: 1.2em; margin: 15px 0; }
        .info { background: rgba(255,255,255,0.2); padding: 15px; border-radius: 10px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚡ Hub Tecnológico Gamma ⚡</h1>
        <p>Centro de excelência em tecnologia!</p>
        <div class="info">
            <p><strong>Localização:</strong> Servidor na LAN4</p>
            <p><strong>IP do Servidor:</strong> 192.168.4.200</p>
            <p><strong>Domínio:</strong> www.gamma-tech.com</p>
        </div>
        <p>Transformando ideias em realidade digital</p>
    </div>
</body>
</html>
EOF'

echo "Páginas web personalizadas criadas."
echo "--------------------------------------------------"

echo "### Passo 12: Configurar DNS/Hosts nos Containers ###"
HOSTS_ENTRIES="
192.168.2.200 www.alpha-empresa.com alpha-empresa.com sitea
192.168.3.200 www.beta-inovacao.com beta-inovacao.com siteb
192.168.4.200 www.gamma-tech.com gamma-tech.com sitec
"
ROUTER_HOSTS_ENTRIES="
192.168.2.200 www.alpha-empresa.com alpha-empresa.com
192.168.3.200 www.beta-inovacao.com beta-inovacao.com
192.168.4.200 www.gamma-tech.com gamma-tech.com
"

echo "Configurando /etc/hosts em host-lan2..."
docker exec host-lan2 bash -c "echo \"${HOSTS_ENTRIES}\" >> /etc/hosts"
echo "Configurando /etc/hosts em host-lan3..."
docker exec host-lan3 bash -c "echo \"${HOSTS_ENTRIES}\" >> /etc/hosts"
echo "Configurando /etc/hosts em host-lan4..."
docker exec host-lan4 bash -c "echo \"${HOSTS_ENTRIES}\" >> /etc/hosts"

echo "Configurando /etc/hosts em roteador1..."
docker exec roteador1 bash -c "echo \"${ROUTER_HOSTS_ENTRIES}\" >> /etc/hosts"
echo "Configurando /etc/hosts em roteador2..."
docker exec roteador2 bash -c "echo \"${ROUTER_HOSTS_ENTRIES}\" >> /etc/hosts"
echo "Configurando /etc/hosts em roteador3..."
docker exec roteador3 bash -c "echo \"${ROUTER_HOSTS_ENTRIES}\" >> /etc/hosts"
echo "Arquivos /etc/hosts configurados nos containers."
echo "--------------------------------------------------"

echo "### Passo 13: Configurar /etc/hosts na Máquina Host (Windows/Linux/Mac) ###"
echo "Lembre-se de configurar o arquivo hosts da SUA MÁQUINA HOST."
echo "No Windows, é C:\Windows\System32\drivers\etc\hosts (execute o Notepad como Administrador)."
echo "No Linux/Mac, é /etc/hosts (use sudo para editar)."
echo "Adicione as seguintes linhas:"
echo "127.0.0.1 www.alpha-empresa.com"
echo "127.0.0.1 www.beta-inovacao.com"
echo "127.0.0.1 www.gamma-tech.com"
echo "--------------------------------------------------"

echo "### Passo 14: Testes de Conectividade ###"
echo "Aguardando um momento para as configurações de rede se propagarem..."
sleep 5

echo "=== Teste de Conectividade entre Hosts ==="
echo "Ping de host-lan2 para host-lan3 (192.168.3.100):"
docker exec host-lan2 ping -c 3 192.168.3.100
echo "Ping de host-lan2 para host-lan4 (192.168.4.100):"
docker exec host-lan2 ping -c 3 192.168.4.100
echo "Ping de host-lan3 para host-lan4 (192.168.4.100):"
docker exec host-lan3 ping -c 3 192.168.4.100
echo "--------------------------------------------------"

echo "=== Teste de Acesso por IP (de host-lan2) ==="
echo "Acessando webserver-lan2 (192.168.2.200):"
docker exec host-lan2 links -dump http://192.168.2.200
echo "---"
echo "Acessando webserver-lan3 (192.168.3.200):"
docker exec host-lan2 links -dump http://192.168.3.200
echo "---"
echo "Acessando webserver-lan4 (192.168.4.200):"
docker exec host-lan2 links -dump http://192.168.4.200
echo "--------------------------------------------------"

echo "=== Teste de Acesso por Domínio ==="
echo "De host-lan2 para www.alpha-empresa.com:"
docker exec host-lan2 links -dump http://www.alpha-empresa.com
echo "---"
echo "De host-lan3 para www.beta-inovacao.com:"
docker exec host-lan3 links -dump http://www.beta-inovacao.com
echo "---"
echo "De host-lan4 para www.gamma-tech.com:"
docker exec host-lan4 links -dump http://www.gamma-tech.com
echo "--------------------------------------------------"

echo "### Passo 15: Acesso da Máquina Host ###"
echo "Após configurar o arquivo hosts da sua máquina, você poderá acessar os sites:"
echo "Por IP (e porta mapeada):"
echo "Site A: http://localhost:8081 ou http://<IP_DO_SEU_DOCKER_HOST>:8081"
echo "Site B: http://localhost:8082 ou http://<IP_DO_SEU_DOCKER_HOST>:8082"
echo "Site C: http://localhost:8083 ou http://<IP_DO_SEU_DOCKER_HOST>:8083"
echo ""
echo "Por Domínio (e porta mapeada, após configurar o hosts do seu SO):"
echo "Site A: http://www.alpha-empresa.com:8081"
echo "Site B: http://www.beta-inovacao.com:8082"
echo "Site C: http://www.gamma-tech.com:8083"
echo "--------------------------------------------------"

echo "### Passo 16: Verificação Final ###"
echo "Status dos containers:"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "Redes Docker 'lan':"
docker network ls | grep lan || true
echo ""
echo "=== Rotas dos Roteadores ==="
echo "--- Rotas Roteador1 ---"
docker exec roteador1 ip route
echo "--- Rotas Roteador2 ---"
docker exec roteador2 ip route
echo "--- Rotas Roteador3 ---"
docker exec roteador3 ip route
echo "--------------------------------------------------"

echo "### Configuração da Topologia Concluída! ###"
echo ""
echo "Para limpar o ambiente, execute os comandos abaixo ou um script de limpeza:"
echo '
# Parar todos os containers relevantes
# docker stop $(docker ps -q --filter "name=roteador" --filter "name=host-" --filter "name=webserver-")

# Remover todos os containers relevantes
# docker rm $(docker ps -aq --filter "name=roteador" --filter "name=host-" --filter "name=webserver-")

# Remover todas as redes
# docker network rm lan1 lan2 lan3 lan4
'
echo "--------------------------------------------------"
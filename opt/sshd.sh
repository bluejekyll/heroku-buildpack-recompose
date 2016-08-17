#!/usr/bin/env bash

if [[ "$DYNO" != *run.* ]] && [ "$JMX_ENABLED" = "true" ]; then
  ssh_port=${SSH_PORT:-"2222"}
  jmx_port=${JMX_PORT:-"1098"}
  rmi_port=${RMI_PORT:-"1099"}
  ip_addr="$(ip -4 a show eth0 | grep inet | sed -E -e 's/.*inet //g' | sed -E -e 's/\/[0-9]+.*//g')"

  if [ -n "$NGROK_API_TOKEN" ]; then
    NGROK_OPTS="${NGROK_OPTS} --authtoken ${NGROK_API_TOKEN}"
  fi

  [ "$JMX_DEBUG" = "true" ] && echo "Starting sshd for $(whoami)@${ip_addr}"
  /usr/sbin/sshd -f /app/.ssh/sshd_config -o "Port 1222"
  ssh -o StrictHostKeyChecking=no -D ${ssh_port} -p 1222 localhost -N &

  # Start the server that can provide user and ip info
  json="{\"dyno\": \"${DYNO}\", \"user\": \"$(whoami)\", \"ip\": \"${ip_addr}\", \"rmiPort\": \"${rmi_port}\", \"jmxPort\": \"${jmx_port}\", \"sshPort\": \"${ssh_port}\"}"
  ruby -rwebrick -e"s=WEBrick::HTTPServer.new(:BindAddress => \"0.0.0.0\", :Port => 2221, :DocumentRoot => Dir.pwd); s.mount_proc('/'){|q,r| r.body='${json}'}; s.start" &

  # Start the tunnel
  ngrok_cmd="ngrok tcp -log stdout ${NGROK_OPTS} ${ssh_port}"
  echo "Starting ngrok tunnel"
  eval "$ngrok_cmd &"

  sleep 1
  ngrok_tunnel=$(curl -s -L localhost:4040/inspect/http | grep -o "tcp://[^:]*:[0-9]*" | sed 's/tcp:\/\///')

  if [ -n "$ngrok_tunnel" ]; then
    echo "JConsole Command: heroku jmx:jconsole $(whoami)@${ip_addr} ${ngrok_tunnel}"
  else
    echo "JConsole Command: [error] could not start ngrok"
  fi

  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS}\
   -Dcom.sun.management.jmxremote\
   -Dcom.sun.management.jmxremote.port=${jmx_port}\
   -Dcom.sun.management.jmxremote.rmi.port=${rmi_port}\
   -Dcom.sun.management.jmxremote.ssl=false\
   -Dcom.sun.management.jmxremote.authenticate=false\
   -Dcom.sun.management.jmxremote.local.only=true\
   -Djava.rmi.server.hostname=${ip_addr}\
   -Djava.rmi.server.port=${rmi_port}"
fi

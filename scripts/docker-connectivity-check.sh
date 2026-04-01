docker network ls -q | while read net; do
  name=$(docker network inspect -f '{{.Name}}' "$net")
  containers=$(docker network inspect -f '{{range .Containers}}{{.Name}} {{end}}' "$net" | xargs)
  [ -n "$containers" ] && echo "[$name] $containers"
done

echo -e "\n--- Reachability Matrix ---"

python3 << 'PYEOF'
import subprocess, json, collections

raw = subprocess.check_output(['docker','network','ls','--format','json']).decode().strip()
nets = json.loads('[' + raw.replace('}\n{','},{') + ']')
container_nets = collections.defaultdict(set)
net_members = {}

for n in nets:
    info = json.loads(subprocess.check_output(['docker','network','inspect', n['Name']]).decode())
    members = [c['Name'] for c in info[0].get('Containers',{}).values()]
    net_members[n['Name']] = members
    for m in members:
        container_nets[m].add(n['Name'])

names = sorted(container_nets.keys())
print(f'\n{len(names)} containers across {len(net_members)} networks\n')
for a in names:
    reachable = set()
    for net in container_nets[a]:
        reachable.update(net_members[net])
    reachable.discard(a)
    if reachable:
        print(f'{a} -> {", ".join(sorted(reachable))}')
    else:
        print(f'{a} -> (isolated)')
PYEOF

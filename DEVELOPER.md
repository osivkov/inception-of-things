# Устройство проекта и обслуживание

Для запуска по шагам используй [README](README.md). Здесь собраны детали, которые нужны при изменении конфигурации, разборе ошибки или подготовке стенда заново.

## Карта репозитория

```text
p1/
├── Vagrantfile              # K3s server и worker
├── Makefile                 # Запуск, проверки, просмотр кластера
├── confs/                   # Описание iotnet и локальные cluster_key*
└── scripts/                 # Общая настройка ВМ, server, worker, verify
p2/
├── Vagrantfile              # Одна ВМ с K3s
├── Makefile
├── confs/                   # Три приложения и Ingress
└── scripts/                 # Установка K3s, применение manifests, verify
p3/
├── Makefile                 # Установка, запуск, GitOps, port-forward
├── confs/
│   ├── cluster.yaml         # K3d iot и публикация порта 8080
│   ├── argocd-install.yaml  # Локальная копия установочных manifests Argo CD
│   ├── argocd-application.yaml
│   ├── namespaces.yaml
│   └── application/         # Deployment, Service и Ingress приложения
└── scripts/                 # Установка инструментов и запуск кластера
bonus/
├── charts/gitlab/           # Локальный chart для GitLab CE
├── confs/                   # Namespace, Application и начальные manifests
└── scripts/                 # Helm, запуск и bootstrap через API GitLab
scripts/
├── prepare.sh               # Общая подготовка libvirt для P1/P2
└── check.sh                 # Проверка подготовленного окружения
```

Корневого Makefile нет. Все примеры `make -C p1 ...` можно выполнить из корня, а внутри `p1` использовать просто `make ...`. Аналогично для P2/P3. Файлы `.vagrant`, ключи `cluster_key*`, `.env` и токены относятся к локальному состоянию и исключены из Git.

## Вычислительные ресурсы и версии

Ресурсы ВМ задаются в Vagrantfile, а Kubernetes requests/limits — в Deployment. Это разные уровни: лимит контейнера не добавляет RAM внешней ВМ.

| Где менять | Текущая конфигурация |
| --- | --- |
| `p1/Vagrantfile` | По умолчанию 1 vCPU / 1024 MiB; server переопределён на 2 vCPU / 2048 MiB |
| `p2/Vagrantfile` | 3 vCPU / 3072 MiB для server |
| `p3/confs/cluster.yaml` | 1 server, 0 agents; CPU и RAM отдельно не ограничены |
| `bonus/charts/gitlab/templates/deployment.yaml` | requests: 1 CPU / 2 GiB; limits: 4 CPU / 4 GiB; `/dev/shm` — memory emptyDir до 256 MiB |
| `bonus/charts/gitlab/templates/storage.yaml` | PVC config 1 GiB, data 10 GiB, logs 2 GiB; StorageClass `local-path` |

У приложений P2 и One More Cup в их Deployment нет собственных requests/limits. При планировании места нужно учитывать также образы, записи контейнеров и компоненты Argo CD. Сумма PVC GitLab в 13 GiB не описывает весь расход диска.

Версии ниже взяты из файлов репозитория. Для изменения версии правь источник в таблице, затем проверяй совместимость и доступность соответствующего релиза.

| Компонент | Значение в проекте | Источник |
| --- | --- | --- |
| Debian box P1/P2 | `debian/trixie64`, `box_version` не задан | Оба Vagrantfile |
| K3s P1 | Версия не закреплена | `p1/scripts/server.sh`, `worker.sh` |
| K3s P2 | `v1.36.5+k3s1` | `p2/scripts/server.sh` |
| K3s P3/bonus | `rancher/k3s:v1.36.5-k3s1` | `p3/confs/cluster.yaml` |
| k3d | `v5.9.0` | `p3/scripts/install.sh` |
| kubectl для P3 | `v1.36.5` | `p3/scripts/install.sh` |
| Argo CD | `v3.3.16` в образах локального install manifest | `p3/confs/argocd-install.yaml` |
| Helm | `v4.3.1` | `bonus/scripts/install-helm.sh` |
| GitLab CE | `19.5.1-ce.0` | `bonus/charts/gitlab/values.yaml` |
| P2 app1 | `nginx:1.28-alpine` | `p2/confs/app1.yaml` |
| P2 app2/app3 | `hashicorp/http-echo:1.0.0` | `p2/confs/app2.yaml`, `app3.yaml` |
| One More Cup | `osivkov/one-more-cup:v1`, для демонстрации `v2` | Deployment в P3 и начальный Deployment bonus |

Docker устанавливается пакетом `docker.io` из репозитория Debian. Его версия в скрипте не закреплена. Установщики k3d, kubectl и Helm проверяют скачанные файлы по опубликованным контрольным суммам.

P1 при новой установке может получить другой K3s, чем P2/P3. Это ограничение воспроизводимости текущих скриптов. Изменение тега K3s в `cluster.yaml` не обновляет существующий кластер: `up.sh` при его наличии запускает его повторно. P2 тоже не переустанавливает уже найденный бинарник K3s при каждом provision.

## Сети и адреса

### P1/P2

Vagrant работает с системным libvirt по `qemu:///system`. У ВМ есть management-сеть Vagrant и отдельная сеть проекта:

| Назначение | Конфигурация |
| --- | --- |
| Management Vagrant | В этом стенде `vagrant-libvirt`, подсеть `192.168.121.0/24`; используется Vagrant для управления и SSH |
| Сеть проекта | `iotnet`, NAT, bridge `virbr56`, gateway `192.168.56.1/24` |
| Server P1 или P2 | `192.168.56.110` |
| Worker P1 | `192.168.56.111` |
| K3s API, к которому присоединяется worker | `https://192.168.56.110:6443` |
| P2 Ingress | `http://192.168.56.110:80` |

Описание `iotnet` лежит в `p1/confs/iotnet.xml` и `p2/confs/iotnet.xml`. Подготовка определяет сеть при отсутствии, включает autostart и запускает неактивную сеть. Уже существующая сеть автоматически не переопределяется при изменении XML — её фактические параметры стоит проверить отдельно:

```bash
virsh -c qemu:///system net-list --all
virsh -c qemu:///system net-dumpxml iotnet
ip -br address
```

Ожидаемые имена доменов — `p1_osivkovS`, `p1_osivkovSW`, `p2_osivkovS`. Если каталог проекта или настройки provider менялись, смотри фактические имена через `virsh list --all`.

P2 передаёт K3s `--flannel-iface eth1`. При переносе на другой box проверь интерфейсы внутри ВМ командой `ip -br address`: имя интерфейса может отличаться. Выбранный интерфейс должен иметь адрес `192.168.56.110`.

### P3/bonus

K3d создаёт кластер `iot`, а kubectl использует context `k3d-iot`. Внешний порт 8080 привязан к loopback Debian, поэтому доступ с Codam организован туннелем.

| Адрес в Debian | Куда ведёт |
| --- | --- |
| `127.0.0.1:8080`, Host `cup.localhost` | Ingress приложения P3 |
| `127.0.0.1:8080`, Host `localhost` | Ingress GitLab после установки bonus |
| `127.0.0.1:8888` при `make -C p3 app` | Service приложения через port-forward |
| `127.0.0.1:9090` при `make -C p3 ui` | Service Argo CD, HTTPS через port-forward |

Два Ingress могут использовать один порт благодаря разным Host. Проверка без браузера:

```bash
curl -H 'Host: cup.localhost' http://127.0.0.1:8080/version.json
curl -H 'Host: localhost' http://127.0.0.1:8080/
```

Вторая команда имеет смысл после запуска GitLab. Для работы только приложения через 8888 Ingress не нужен: port-forward обращается прямо к Service.

## Как выполняется provisioning

### P1

`make up` сначала вызывает `keys`, затем `prepare`, `check`, `vagrant up --provider=libvirt` и `test`. В текущем Makefile нет `--no-parallel`.

`common.sh` на обеих ВМ устанавливает инструменты и SSH-ключи, добавляет имена узлов в `/etc/hosts` и отключает swap. `server.sh` устанавливает K3s в server-режиме. `worker.sh` получает `/var/lib/rancher/k3s/server/node-token` с сервера по SSH и устанавливает agent с адресом API и токеном. Число попыток получения токена ограничено; отсутствие токена завершает provision ошибкой.

K3s в гостевых ВМ использует свой контейнерный runtime. Для P1/P2 не требуется устанавливать Docker на каждой ноде; Docker в основной Debian нужен для K3d в P3.

Vagrant использует собственное состояние SSH в `.vagrant`. Пара `confs/cluster_key*` — отдельный механизм для связи двух гостей. Target `keys` сохраняет существующий приватный ключ и восстанавливает `.pub` из него. В P2 нет обмена токеном между ВМ, поэтому копирования этой пары туда нет.

В учебной конфигурации есть послабления: отключена проверка host key для `192.168.56.*`, а kubeconfig server создаётся с mode `644`. Для общего или публичного сервера такие настройки нужно пересмотреть. На worker административный kubeconfig автоматически не настраивается.

### P2

Vagrant передаёт папку `confs/` в `/home/vagrant/confs` гостя. `server.sh` устанавливает K3s, если он ещё не найден, запускает службу, ждёт API и Ready-ноду, применяет приложения и Ingress, затем ждёт rollout трёх Deployment.

App1 получает HTML из ConfigMap `app1-page` и отдаёт его через nginx на порту 80. App2 и app3 слушают 5678; их Service принимают запросы на 80 и направляют их на 5678. Правило Ingress без `host` ведёт к app3. Все эти ресурсы находятся в namespace `default`.

После изменения передаваемых файлов нужен `vagrant provision osivkovS` из `p2`. Редактирование локального YAML само по себе не меняет ресурсы внутри уже запущенной ВМ.

### P3 и bonus

`p3/scripts/up.sh` создаёт `iot` при отсутствии или запускает существующий, переключает текущий kubectl context, ждёт ноду, применяет namespaces и локальный install manifest Argo CD. Затем ждёт Deployments и контроллер Application.

Обычный запуск применяет GitHub Application. Bonus вызывает этот же скрипт с `SKIP_APPLICATION=true`, затем устанавливает GitLab командой Helm и работает с GitLab API. Режим `--setup-only` останавливается после готовности GitLab, чтобы пользователь создал токен. Он сохраняет текущий источник Application, если тот уже был настроен.

Скрипты запуска и `make verify` — разные уровни проверки. При запуске через `make -C p3 up` или `bonus-up` выполняется и итоговая проверка приложения. Прямой вызов `bonus/scripts/up.sh` проверяет синхронизацию и здоровье Application, но не выполняет все HTTP-проверки из Makefile.

## GitOps и репозитории

| Режим | URL источника | Ветка | Каталог |
| --- | --- | --- | --- |
| P3 | `https://github.com/osivkov/inception-of-things.git` | `main` | `p3/confs/application` |
| Bonus | `http://gitlab.gitlab.svc.cluster.local/osivkov/iot.git` | `main` | `.` |

Обе конфигурации описывают **одно** Application `argocd/playground`, разворачивающее приложение в `dev`. Применение второй конфигурации меняет источник первой. Автосинхронизация включает `prune` и `selfHeal`: Argo CD приводит ресурсы к состоянию из Git. Ручная правка Deployment через kubectl не заменяет коммит. Подробнее — [политика синхронизации Argo CD](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/).

В рабочем репозитории `origin` используется для GitHub, `vogsphere` — для сдачи. Новый клон из Vogsphere может иметь другой `origin`. URL в Argo CD при этом сам не меняется: проверь `git remote -v` и `spec.source.repoURL` перед демонстрацией.

Bootstrap bonus создаёт публичные группу и проект, затем добавляет `deployment.yaml` и `service.yaml` первым коммитом, только если репозиторий пуст. Он не обновляет существующую ветку файлами из локальной заготовки. Параметры `GITLAB_GROUP` и `GITLAB_PROJECT` меняют адрес bootstrap-проекта, но URL в `bonus/confs/argocd-application.yaml` остаётся заданным явно.

GitLab в этой конфигурации обслуживает Git по HTTP. Отдельный GitLab SSH Service не опубликован; настраивать учебную пару P1 для GitLab не требуется.

## Перед отправкой на сдачу

Свежий клон получает только закоммиченные файлы. Makefile частей и скрипты `verify.sh` должны быть в Git, даже если на рабочем стенде они уже запускаются. Проверить список и оставшиеся изменения можно так:

```bash
git status --short
git diff --check
git ls-files p1/Makefile p1/scripts/verify.sh p2/Makefile p2/scripts/verify.sh
git remote -v
```

Отправляй сдаваемый коммит в `vogsphere`, а изменения GitOps для P3 — в GitHub. Это разные назначения. Локальное наличие SSH-ключей не означает, что они попадут в клон: `cluster_key*` намеренно исключены из Git и создаются на месте при необходимости.

## Что на самом деле проверяют команды

| Команда | Что проверяет | Что посмотреть отдельно |
| --- | --- | --- |
| `make -C p1 check` | Vagrantfile, доступ к libvirt, Intel EPT, активность и autostart iotnet, конфликт с P2 | Состояние Kubernetes после запуска |
| `make -C p1 test` | SSH в оба гостя, hostname/IP, службы K3s, kubectl server, две Ready-ноды | Все системные Pod и события |
| `make -C p2 test` | Гость, K3s, одна Ready-нода, rollout приложений, 3 ready replicas app2, HTTP по трём Host | Детали Ingress и Service: скрипт их выводит, но не сравнивает весь YAML |
| `make -C p3 verify` | Application Synced/Healthy, rollout, `/healthz` и версия v1/v2 внутри контейнера | Доступ через браузер, Service/Ingress и нужная Git-ревизия |

Успешный `verify` в P3 принимает и v1, и v2. Чтобы доказать обновление именно до v2, проверь текущий image, Git revision и `/version.json`. Проверка внутри Pod не доказывает, что туннель пользователя открыт.

Не все ошибки provisioning одинаково видны: в P1 итоговый диагностический `kubectl get nodes` у server допускает ошибку, а `make test` запускается отдельно после `vagrant up`. Поэтому окончательный ориентир — результат `test` и фактическое состояние кластера.

## Вложенная виртуализация

На этом стенде путь выглядит так: VirtualBox → Debian → KVM → гостевые ВМ. Ранее в VBox.log наблюдался `VERR_VMX_INVALID_GUEST_STATE` с переходом в `GURU_MEDITATION`. Это подтверждает ошибку VMX, но не устанавливает её триггер. Нехватка RAM как причина этого сбоя не доказана.

Текущий `scripts/prepare.sh` отключает Intel EPT через `kvm_intel ept=0` и записывает настройку в `/etc/modprobe.d/iot-kvm.conf`. Если параметр ещё не выставлен, скрипт требует остановить все активные libvirt-ВМ, чтобы перезагрузить модуль. Это настройка всей основной ВМ, а не отдельной части проекта. Скрипты рассчитаны на используемый Intel-стенд.

Эффективность этого обходного пути против Guru Meditation не подтверждена. Последовательный запуск можно использовать как отдельный диагностический опыт после обычных `keys`, `prepare`, `check` из P1:

```bash
vagrant up --provider=libvirt --no-parallel
make test
```

Это команды из каталога `p1`; такой опыт не считается исправлением низкоуровневого сбоя. Для проверки аппаратного ускорения уже запущенного домена:

```bash
virsh -c qemu:///system qemu-monitor-command p1_osivkovS --hmp 'info kvm'
```

При необходимости повышенных прав выполни эту диагностическую команду через `sudo`. Ответ `kvm support: enabled` подтверждает использование KVM, но не гарантирует устойчивость вложенной виртуализации.

В показаниях памяти важно различать уровни. `available` внутри Debian показывает запас гостя; он не обязан сразу возвращаться физическому хосту. Строки потоков VirtualBox в htop нельзя складывать как независимые процессы. Перед изменением выделенной RAM проверяй и Debian, и физический компьютер.

## Если что-то не запускается

Начинай с компонента, который выдал ошибку. Ниже команды для уже созданного окружения; запускать новую инфраструктуру для чтения этих заметок не нужно.

| Симптом | Что проверить |
| --- | --- |
| `make check` не проходит до запуска ВМ | `virsh -c qemu:///system list --all`, `net-list --all`, доступ к EPT и `vagrant validate` в нужной части |
| Worker отсутствует в `get nodes` | Службу `k3s-agent`, доступ worker к server по SSH, логи server и agent |
| Pod в `Pending` или `CrashLoopBackOff` | `describe pod` и события в нужном namespace; затем логи контейнера |
| P2 по IP показывает app3 | Это штатный default route; для app1/app2 нужен соответствующий Host |
| P2 не отвечает вообще | `eth1`, Traefik, Service endpoints, маршруты и HTTP с Debian до проверки туннеля |
| Docker отвечает `permission denied` | Доступ текущего пользователя; после установки и изменения групп — новый login-сеанс |
| Argo CD не меняет image | Активный repoURL, ветку, Git revision и факт push в этот репозиторий |
| В браузере connection refused | Нужный port-forward в Debian, SSH-туннель на Codam и свободный локальный порт |
| GitLab не готов | Pod, PVC, события namespace `gitlab`, свободную RAM и место на диске |

Для P1 основные диагностические команды уже есть в Makefile:

```bash
make -C p1 cluster-check
make -C p1 logs-server
make -C p1 logs-worker
```

Для P2: `make -C p2 all-checks` и `make -C p2 logs`. Для P3:

```bash
kubectl --context=k3d-iot -n argocd get application playground -o yaml
kubectl --context=k3d-iot -n dev get pods -o wide
kubectl --context=k3d-iot -n dev get events --sort-by=.metadata.creationTimestamp
```

Предупреждение `[fog][WARNING] Unrecognized arguments: libvirt_ip_command` само по себе не доказывает причину ошибки. После `Fog::Errors::TimeoutError` при остановке смотри `virsh list --all`: сообщение об ошибке ещё не говорит, какие ВМ остались работать. Если упала сама внешняя VirtualBox-ВМ, её VBox.log нужно читать на физическом компьютере.

## Очистка между эвалами

Обычная остановка и удаление — разные действия. `halt` и `k3d cluster stop iot` сохраняют окружение. Для нового развёртывания P1/P2 используй `make -C p1 destroy` и `make -C p2 destroy` из того клона, которому принадлежат ВМ. Для P3 удали существующий `iot` через `k3d cluster delete iot`.

После удаления проверь libvirt и Docker, а не только локальный Vagrant status:

```bash
virsh -c qemu:///system list --all
virsh -c qemu:///system pool-list --all
virsh -c qemu:///system vol-list --pool default
k3d cluster list
docker ps -a
docker volume ls
docker network ls
```

`default` здесь — имя storage pool в этом стенде. В другом окружении возьми имя из `pool-list`. Vagrant box images остаются кэшем для следующих ВМ. Диски конкретных машин обычно называются `p1_osivkovS.img`, `p1_osivkovSW.img` и `p2_osivkovS.img`.

Если домен остался от старого клона, сначала установи его происхождение и проверь диск:

```bash
virsh -c qemu:///system dumpxml p2_osivkovS
virsh -c qemu:///system domblklist p2_osivkovS --details
```

В XML vagrant-libvirt обычно записывает `Source: .../p2/Vagrantfile`. Не удаляй том только потому, что он похож по имени, и не стирай `.vagrant` до удаления её машин: так теряется связь с доменом. Общие сети `iotnet` и `vagrant-libvirt` можно сохранить; `prepare.sh` при следующем запуске подготовит сеть проекта.

Docker-образы тоже можно оставить для ускорения следующего старта. Если нужна очистка кэша, посмотри `docker image ls` и удали конкретные теги через `docker image rm`. Общий `docker system prune --volumes` здесь не нужен. Существующие ключи P1 сохраняются независимо от удаления ВМ.

## Данные GitLab

Chart хранит конфигурацию, данные и логи в трёх PVC `local-path`. Нормальная остановка K3d их сохраняет. В шаблоне PVC есть `helm.sh/resource-policy: keep`, поэтому удаление Helm release не означает, что PVC тоже исчезнут. При этом удаление самого кластера уничтожает данные внутри его узлов. Поведение аннотации описано в [документации Helm](https://helm.sh/docs/howto/charts_tips_and_tricks/).

Чтобы подготовить резервную копию:

```bash
kubectl --context=k3d-iot -n gitlab exec deploy/gitlab -- gitlab-backup create
kubectl --context=k3d-iot -n gitlab exec deploy/gitlab -- ls -lh /var/opt/gitlab/backups
```

Скопируй нужный архив за пределы кластера. Отдельно сохрани `/etc/gitlab/gitlab-secrets.json` и конфигурацию из config PVC: одного архива приложения недостаточно. Для восстановления требуется соответствующая версия GitLab. Порядок действий — в официальных инструкциях [backup](https://docs.gitlab.com/administration/backup_restore/backup_gitlab/) и [restore](https://docs.gitlab.com/administration/backup_restore/restore_gitlab/); собственного restore-скрипта в проекте нет.

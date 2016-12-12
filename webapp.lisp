;; given:
;; - network
;; - nodes
;; - stacks
;; - this


(stack firewall
       (vars
        :all 'closed
        :open nil)
       (install-package 'iptables)
       (configure-iptables this.vars))

(stack ssh
       (vars :port 22)
       (layer firewall :open this.port))

(stack common
       (layer ssh))

(stack my-webapp
       (vars
        :cachedir "/tmp/my-webapp/cache"
        :port 3000
        :db "localhost:${stacks.mysql.port}")
       (layer common)
       (layer firewall :open this.port)
       (install-package 'my-webapp)
       (run-daemon "${my-webapp}/bin/webapp ${this.port}" :watchdog true))

(stack mysql
       (vars :port 3306)
       (layer common)
       (layer firewall :open this.port)
       (install-package 'mysql)
       (run-daemon "${mysql}/bin/mysqld --port ${this.port}"))

(stack haproxy
       (vars
        :from 80
        :to "localhost"
        :match ".*")
       (layer common)
       (install-package 'haproxy)
       (haproxy-configure this.vars))

(node www
      (layer my-webapp :db "${network.db.address}:${network.db.port}"))

(node db
      (layer mysql))

(node proxy (network nodes)
      (layer haproxy
             :port 80
             :to nodes.www.my-webapp.port
             :match "network.www-[0-9]+"))

(network
 '(www 5)
 'db
 'proxy)

(define default-providers
  :virtualbox '(:cores 1 :memory 256)
  :libvirt '(:cores 1 :memory 256)
  :aws '(:flavor "m1.large")
  :gce '(:type "n1-standard-8"))

(provision
 :www default-providers
 :db default-providers
 :proxy (override default-providers
                  :aws '(:flavor "t1.medium")
                  :gce '(:type "n1-standard-4")))

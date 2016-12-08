
(import stacks :all)                        ;import stacks (e.g. firewall) defined in stacks.lisp

(stack hadoop-setup
       (vars
        :store-path "/hdfs"
        :hdfs-name "mycompany"
        :permissions-enabled false
        :namenode-rpc-port 8020
        :namenode-http-port 50070
        :namenode-dir "file://${this.store-path}/namenode"
        :qjournal-port 8485
        :datanode-data-dir "file://${this.store-path}/datanode"

        ;; when ha-mode
        :ha-mode false
        :journalnode-edits-dir "file://${this.store-path}/journalnode" 
        :namenode-names '("nn1" "nn2")
        :namenode-nodes (required (when this.ha-mode) :type 'node)
        :zookeeper-address (required (when this.ha-mode) :type 'string :example "zk://h1:2181,h2:2181,h3:2181")
        :fencing-method 'sshfence
        :automatic-failover true)

       (install-package 'hadoop)
       (hadoop-configure this)

       (not (dir-exists? "${this.store-path}")
            (make-dir "${this.store-path}")))


(stack hadoop-namenode
       (inherit hadoop-setup)

       (when this.ha-mode
         (layer firewall
                :open '(this.namenode-rpc-port
                        this.namenode-http-port
                        this.qjournal-port))) 

       (define-daemon hdfs-namenode
         :run "hdfs namenode"
         :logfile "path/to/logfile")

       ;; first run: format namenode
       (define-daemon-preexec hdfs-namenode-format
         :for hdfs-namenode
         (shell-when-file-exists "${this.store-path}/formatted"
                                 (command "hdfs namenode -format -force")
                                 (when this.ha-mode
                                   (command "hdfs namenode -initializeSharedEdits -force")
                                   (command "hdfs zkfc -formatZK -force"))
                                 (command "touch ${this.store-path}/formatted")))

       (run-daemon hdfs-namenode :watchdog true))

(stack hadoop-datanode
       (inherit hadoop-setup)
       (run-daemon hdfs-datanode
                   :run "hdfs datanode"
                   :cwd "${this.store-path}"
                   :logfile "datanode.log"
                   :watchdog true))

(stack yarn
       ...)

(stack hadoop-yarn-resourcemanager
       (inherit yarn)
       ...)

(stack hadoop-yarn-journalnode
       (inherit yarn)
       ...)

(stack hadoop-metadata
       (layer hadoop-namenode)
       (layer hadoop-yarn-resourcemanager)
       (layer hadoop-yarn-journalnode))

(stack zookeeper
       (vars
        :port 2181
        :id 'required
        :peers 'required)
       (layer firewall :open this.port)
       (install-package 'zookeeper)
       (zookeeper-configure this.vars)
       (run-daemon "zookeeper" :watchdog true))

(node metadata
      (let
          (metadata-nodes (filter-network "metadata.*"))
        (layer zookeeper
               :id (index-of this metadata-nodes)
               :peers (filter-network "metadata"))
        (layer hadoop-metadata
               :hdfs.ha-mode true
               :hdfs.namenode-nodes metadata-nodes
               ...)))

(node datanode
      (layer hadoop-datanode))

(network
 '(datanode 10)
 '(metadata 3))

(provision
 :metadata '(:aws (:flavor "r4.8xlarge"))
 :datanode '(:aws (:flavor "r4.16xlarge")))

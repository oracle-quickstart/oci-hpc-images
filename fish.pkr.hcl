region = "ap-kulai-1"
ad = "VAEn:AP-KULAI-1-AD-1"
compartment_ocid = "ocid1.tenancy.oc1..aaaaaaaayk5ztewzgel2vc5zevaapemqlyjphfjoafwirmnmgj444tsldlea"
shape = "VM.Standard.A1.Flex"
subnet_ocid = "ocid1.subnet.oc1.ap-kulai-1.aaaaaaaayk5ts7eipta6rfsemfmnglbujl2d5rzxw3konuvu7jq7isr7wakq"
# access_cfg_file = "/home/opc/.oci/config"
# access_cfg_file_account = "DEFAULT"
# security_token_file = "/home/ubuntu/.oci/sessions/DEFAULT/token"
use_instance_principals = true
OpenSSH9 = true
shape_config = {
    ocpus = 8
    memory_in_gbs = 32
}

release=9

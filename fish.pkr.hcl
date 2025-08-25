# This info needs to be populated correctly for the instance builder to be launched.
region = "ap-kulai-1"
ad = "VAEn:AP-KULAI-1-AD-1"
shape = "VM.Standard.A1.Flex"
subnet_ocid = "ocid1.subnet.oc1.ap-kulai-1.aaaaaaaayk5ts7eipta6rfsemfmnglbujl2d5rzxw3konuvu7jq7isr7wakq"


compartment_ocid = "ocid1.tenancy.oc1..aaaaaaaayk5ztewzgel2vc5zevaapemqlyjphfjoafwirmnmgj444tsldlea"
use_instance_principals = true
OpenSSH9 = true # Needed for Ubuntu24
shape_config = {
    ocpus = 8
    memory_in_gbs = 32
}
release=6

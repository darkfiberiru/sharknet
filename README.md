# Sharknet
Sharknet is a tool designed to allow simple autoconfigured direct connectivity from a NAS to a client system. Commonly these direct connections will be high speed expensive ports. This removes need for switches and simplifies network setup. This setup is only recommended for certain niche use cases of FreeNAS. This is especially important in certain Media and Entertainment workflows where small shops with little to no IT resources may need exceptional storage performance with minimal components and configuration.

While sharknet is external to FreeNAS it is designed to integrate seamlessly after setup. Registering itself appropriately across FreeNAS so FreeNAS understands the parts it needs to and ignores the ones it doesn't.


An example usage is to support a 2018 IMac Pro which only has one 10GBASE-T connection. Many FreeNAS systems have onboard 10GBASE-T connections. Using sharknet directly connecting the two 10GBASE-T ports will five the iMac an ip address, 10g connectivity to the FreeNAS, and internet all in one cable. No configuration is needed on the mac side. From the mac you will then be able to go to nas.local.ixsystems.com to access the FreeNAS and all of it's services.

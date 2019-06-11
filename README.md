# sharknet
Sharknet is a tool designed to allow simple autoconfigured direct connectivity from a NAS to a client system. Commonly these direct connections will be highspeed expensive ports. This removes need for switches and simplifies network setup. This setup is only recommended for certain niche use cases of FreeNAS. This is especially important in certain Media and Entertainment workflows where small shops with little to no IT resources may need exceptional storage performance with minmial componets and configuration.

While sharknet is external to FreeNAS it is designed to integrate seamlessly after setup. Registering itself appropriatly across FreeNAS so FreeNAS understands the parts it needs to and ignores the ones it doesn't.


An example usage is a 2018 imac pro only has a single 10g copper connection and many freenas systems have onboard 10g-baset connections. Using sharknet if you plug the two directly together then the mac will get an ip address, 10g connectivity to the freenas and internet all in one cable. No configuration needed on the mac side. From the mac you would then be able to go to nas.local.ixsystems.com to access the FreeNAS and all of it's services

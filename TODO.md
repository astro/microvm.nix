# TODO

## Structure Notes

I believe that the documentation needs to be restructured in the following way:


1. Intro

Quick microvm configuration

    2. microvm module

    3. Running a MicroVM as a package

Advanced microvm configuration

    4. Preparing host for Declarative microvm

        4.1. A simple network setup

        4.2. Advanced network setup

        4.3. Host systemd services
        
        4.4. Host options reference

    5. Declarative approach

    6. Imperative approach
    
    7. deploy via ssh

Configuration options

    8. configuration options for the **host**

    9. configuration options for the **VMs**

Important

    10. Conventions

    11. Configuration examples

    12. Frequently Asked Questions 


## General Notes

- [ ] its important to include the intended use case of microvm, and how the user is meant to interact with it

    * (from what i understand) the recommended way of using microVMs is with declarative deployment, but imperative management. This needs to be clearly stated, and most documentation must be focused on that way of deployment.

    * an overview of the such setup and its workflow has to be described in great detail

- [ ] ways of interacting with a declared VM. 

    * Its uni intuitive that there is no easy way of directly interacting with a VM if its deployed in any way except for ```nix run .#my-microvm```, this must be explained. 

    * In order to cover more use cases, an in detail explanation of how to connnect to tty of a declared vm must also be created, as most users will want this.


- [ ] all explanations should be made step by step, with an assumption that the reader is poorly familiar with nix.

    * This is important not only for new users, but for anyone trying to debug, or has gaps in knowledge 





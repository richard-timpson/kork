# Local kork Build Validation

This is a script which can be used to locally validate that a build of kork works.

It's intended use is for local development only, as the process to build kork and update the kork versions in each microservice is already fully automated through CI. The intention with this script is that it will help to validate kork changes during development, before pull requests are merged.

The script runs a local build of kork, loops through every dependent microservice, updates the kork version in gradle.properties to point to the local kork version, and runs a build of each microservice to verify that new local kork package doesn't break anything in the dependent services

## Directory Structure
The script makes a few assumptions about the directory structure for all other microservices. The directory structure should look something like the following

```bash
pwd
/Users/richard.timpson/Documents/orgs/spinnaker
ls -l
total 0
drwxr-xr-x  69 richard.timpson  staff  2208 Apr 27 15:21 clouddriver
drwxr-xr-x  61 richard.timpson  staff  1952 Apr  4 15:48 deck
drwxr-xr-x  52 richard.timpson  staff  1664 Apr 27 15:40 echo
drwxr-xr-x  39 richard.timpson  staff  1248 Apr 27 15:42 fiat
drwxr-xr-x  45 richard.timpson  staff  1440 Apr 27 15:42 front50
drwxr-xr-x  45 richard.timpson  staff  1440 Apr 27 15:44 gate
drwxr-xr-x  37 richard.timpson  staff  1184 Apr  4 20:44 halyard
drwxr-xr-x  35 richard.timpson  staff  1120 Apr 27 15:46 igor
drwxr-xr-x  68 richard.timpson  staff  2176 Apr 27 16:28 kork
drwxr-xr-x  87 richard.timpson  staff  2784 Apr 27 15:47 orca
drwxr-xr-x  33 richard.timpson  staff  1056 Apr 27 16:02 rosco
```

In other words, kork should exist in the same root directory as all other dependent microservices.

## Use
**Note**: Please run `./local_kork_validation.sh --help` for all the arguments and the full documentation

The script by default (with no args) will run full validation for kork and all other services, i.e, it runs the kork build with tests and runs all microservice builds with tests.

### Skip unit tests

To run the validation without executing tests (which is useful as a dry run sanity check), run

`./local_kork_validation.sh --skip-tests`

### Customize microservices to validate
It's also possible skip certain microservices. For example, to skip clouddriver, run

`./local_kork_validation.sh --skip-repos "clouddriver"`

Another example would be to only run the validation for clouddriver (skip every repo but clouddriver)

`./local_kork_validation.sh --skip-repos "echo,fiat,front50,gate,igor,orca,rosco"`

To skip tests **and** customize the repo list, use something like

`./local_kork_validation.sh --skip-tests --skip-repos "clouddriver"`

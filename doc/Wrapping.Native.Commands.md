# Native Commands in PowerShell - A New Approach

In this two part blog post I'm going to investigate how PowerShell can take better advantage of native executables.
In the first post, I'm going to discuss a few of the ways that PowerShell can better incorporate native executables
into our object oriented world and how we can use these tools to better fit into our model of more discrete operations.
In the second post, I'll be exploring some of the work to more easily convert the use of native tools into the
cmdlet/object output model of PowerShell.

PowerShell provides a number of benefits to it's users

- consistent parameter naming for similar uses
- a single parameter parser so errors about mis-parameter use are consistent across all commands
- output consisting of objects (no text parsing)
- common way to get help
- cross platform consistency
- easy execution of existing tools

Some of these are not unique to PowerShell, and many tools also provide some of these behaviors.
Every shell has the capability of executing utilities, you could argue that this is the main use for a _shell_
and PowerShell is no different.
Additionally, UNIX systems have man pages and the _mostly_ ubiquitous `--help` for getting assistance directly from the command.
Microsoft Windows may provide `/?`, but the point is the same.
It's a way to get help from the application.

PowerShell spent much of its first decade in building up a large number of tools for system management,
but does not have cmdlets for all aspects of administration on all platforms.
There are a number of very excellent and vital standalone tools that target the scenarios for administration and management very well.
Some of these tools have existed for many years and have grown in functionality and complexity including their own 'mini-language'.
Examples of these include:

- Package managers such as `apt`, `yum`, `brew`
- Source control applications such as `git`
- The utility for Docker management `docker`
- The utility for Kubernetes management `kubectl`
- `netsh.exe` which is _the_ command for automating Microsoft Windows network configuration
- The Microsoft Windows utility `net.exe` for creating and managing local user accounts on Microsoft Windows

The authors of these tools have their own specific approach to solving the problems that are uniquely theirs.
In some cases, utilities such as `awk` and `sed`, an entire new mini-languages were created.
Mostly these are glue utilities, they were created to manipulate the outputted data into a form to be more easily
filtered, or changed to fit a specific need.

## Solution Options

If I want to have the familiar, comfortable PowerShell experience, there are only a few options that are available to me.

- You can re-implement the tool in managed code or script
- You can call web based APIs. For example, SWAGGER provides a very easy way to do this
  - <https://github.com/Azure/autorest> is one example
- You can wrap the native application in a PowerShell script
- I can just use the tool as is without change

### Reimplementation

There a many benefits in a complete rewrite of a command:

- The expression of behavior can be made more "natural" to the new environment
- Performance issues can be addressed
- New code means that new technologies can be used advantageously

#### Issues with Reimplementations

The biggest issue with reimplementation is probably the amount of work that is needed to achieve behavior expressed in the original.
This is especially the case if the reimplementor is not intimately familiar with the workings of the tool.
Another issue with reimplementation is that you need to continue to track changes in the original code.
This can be a challenge as depending on the activity and updates in the tool, wholescale changes can occur that then need to be reimplemented,
or the reimplementation will be out of date.
Worse, if the the command is the client side of a client/server app, changes in the server may negatively effect the reimplementation.

### API wrapping

Many native apps use a REST endpoint to retrieve data.
These can be used to interact with the data endpoint, retrieve data from it and then present it to the user.
For example, the following shows how you could present the data about kubernetes pods by interacting with the REST endpoint and display the data.
In comparison is the output from the native command.

```powershell
kubectl get pods; get-pods.ps1|ft

NAME                     READY   STATUS      RESTARTS   AGE
hello-1589924940-rv2v2   0/1     Completed   0          3m5s
hello-1589925000-gs5n7   0/1     Completed   0          2m5s
hello-1589925060-j4bjc   0/1     Completed   0          65s
hello-1589925120-jvxtd   0/1     Completed   0          4s

Name                   Ready Status    Restarts Age
----                   ----- ------    -------- ---
hello-1589925000-gs5n7 0/1   Completed        0 00:02:05.2602110
hello-1589925060-j4bjc 0/1   Completed        0 00:01:05.2607090
hello-1589925120-jvxtd 0/1   Completed        0 00:00:04.2612030
```

#### Issues with API wrapping

The most impactful issues with this approach are about authentication and complexity.
Also, simple API wrapping generally results in a command that is _developer_ rather than _administrator_ focused.
There is quite a bit of logic wrapped up in a command to avoid just calling the API.
The script that produced the output can be used to illustrate some of the problems with this approach

```powershell

# retrieve data from REST endpoint
$baseUrl = "http://127.0.0.1:8001"
$urlPathBase = "api/v1/namespaces/default"
$urlResourceName = "pods"
$url = "${baseUrl}/${urlPathBase}/${urlResourceName}"
$data = (invoke-webrequest ${url}).Content | ConvertFrom-Json

# manipulate data for output
foreach ( $item in $data.Items ) {
    $replicaCount = $item.status.containerstatuses.count
    $replicaReadyCount = ($item.status.conditions | Where-Object {$_.Ready -eq "True"}).Count
    $Age = [datetime]::now.touniversaltime() - ([datetime]$item.status.conditions.lastTransitionTime[-1])
    [pscustomobject]@{
        Name     = $item.metadata.name
        Ready    = "{0}/{1}" -f $replicaReadyCount, $replicaCount
        Status   = @($item.status.containerstatuses.state.terminated.reason)[-1]
        Restarts = $item.status.containerstatuses.restartcount
        Age      = $age
        }
}
```

In the above example, the work of the script is broken into 2 sections.

- a section that gets the data from the REST endpoint
- a section that converts the JSON data into an object that has the specific properties I want to see

There are a few shortcuts in the first section:

- I'm not providing a parameter to retrieve different resources
- I'm not using any authentication
- I'm using what I already know with regard to the actual `url` to retrieve data

The second section that alters the data to a form I need by converting the JSON to a view I'm more comfortable with.
With regard to the output, I made a decision to handle the presentation of elapsed time in a way that most cmdlets do.

This approach casts the problem in the light of the developer again.
Much like re-implementation, there is a certain amount of code that is required just to _get_ the data,
and with this example I'm showing the absolute simplest case since I'm not doing any authentication and I \_know what the endpoint to which I'm connecting.
The part that is familiar is the second part of the script that creates an object that I can use with our other filters.
This can be done in many different ways, I could have written this code using `Select-Object` as follows:

```powershell
$data.Items | Select-Object -Property @{ N = "Name"; E = {$_.metadata.Name}},
     @{ N = "Ready"; E = { "{0}/{1}" -f ($_.item.status.conditions|Where-Object {$_.Ready -eq "True"}).Count, $_.status.containerstatuses.count}},
     @{ N = "Status"; E = { @($_.status.containerstatuses.state.terminated.reason)[-1]}},
     @{ N = "Restarts"; E = { $_.status.containerstatuses.restartcount}},
     @{ N = "Age"; E = { [DateTime]::now.touniversaltime() - [datetime]($_.status.conditions.lastTransitionTime[-1])}}
```

Regardless of how it's written, I believe that the second section is well understood by most PowerShell scripters,
but the first section is less known and needs knowledge about the service and how to authenticate.

_However_, I think the biggest issue with this approach is that for anything complicated (or anything more complicated than simple "gets")
is that the REST APIs are developer constructs _made for developers_.
This means that if you want to use these REST APIs, you need to put on a developer hat and produce a solution that has a different set of problems.
This is what the developer did initially.
They took the available APIs (REST or otherwise) and built up the administrative experience in the application,
sheltering the admin from the programming problems.
In the kubernetes example above, if I needed to query the REST endpoint to see what types of resources were available,
that means more calls back and forth from the service.

### Native Application Wrapping

Because it is possible to call native applications easily from within PowerShell,
it is possible to write a script that provides a more PowerShell-like experience.
It can provide parameter handling such as prompting for mandatory parameters and tab-completion for parameter values.
It can take the text output from the application and parse it into objects.
This allows you to take advantage of all the post processing tools such as `Sort-Object`, `Where-Object`, etc.

The previous example can be greatly simplified and written as follows:

```powershell
$data = kubectl get pods -o json | ConvertFrom-Json
$data.Items | Select-Object -Property @{ N = "Name"; E = {$_.metadata.Name}},
     @{ N = "Ready";    E = { "{0}/{1}" -f ($_.item.status.conditions|Where-Object {$_.Ready -eq "True"}).Count, $_.status.containerstatuses.count}},
     @{ N = "Status";   E = { @($_.status.containerstatuses.state.terminated.reason)[-1]}},
     @{ N = "Restarts"; E = { $_.status.containerstatuses.restartcount}},
     @{ N = "Age";      E = { [DateTime]::now.touniversaltime() - [datetime]($_.status.conditions.lastTransitionTime[-1])}}
```

PowerShell has tools that make it easy to convert structured text.
In this case, `kubectl` has an option to output JSON.
The `ConvertFrom-Json` cmdlet converts that to an object.
Then we can use the same code to present data.

This approach has some advantages:

- We avoid the entire problem of how to authenticate to access the data
  - We are protected from changes in the service and API endpoint
- changes in the tool shouldn't affect the wrapper or can be easily managed by simple changes to the script
- If the application supports uniform cross-platform execution, the wrapper can be run easily on whatever platform is needed

One of my first experiences with this was a very simple processes of getting information about PDF files with the tool `pdfinfo.exe`.
I needed to retrieve information from a very large set of set of PDF files (1000s).
I wrapped both the parameters and the output to have it behave much like a regular cmdlet.
Of course, I could have just used the native app, but I wanted a command I could pipe files to and filter the results:

```powershell
$a = get-childitem -rec -filt *.pdf | Get-PdfInfo | Where-Object { $_.subject -like "sibelius" }
$sa | ft file,title,subject,pagesize

File           Title                        Subject            Pagesize
----           -----                        -------            --------
SIB08.pdf      Sibelius - Finlandia, Op. 26 Trumpet            720x936 pts
SIB08.pdf      Sibelius - Finlandia, Op. 26 Viola              720x936 pts
...
SIB08.pdf      Sibelius - Finlandia, Op. 26 Cello              720x936 pts
SIB08.pdf      Sibelius - Finlandia, Op. 26 Bassoon            720x936 pts
```

The point of all this was that I wanted a native PowerShell experience rather than the experience provided by the standalone application.

#### Issues with application wrapping

The issues are roughly the same as above.
There is a certain amount of programming needed to call the application.
There is some programming needed to convert the text output to objects so they can participate in the PowerShell pipelines.
The significant difference is that unlike the REST approach is that I don't have extra work determining _how_ to invoke the app.
I can just invoke it.
Further, it seems a more natural use of the tool.
I'm familiar with the workings of the tool.
I'm just parsing the output into objects.
It's important to note that if the tool emits `JSON`, `XML`, or other structured data, a lot less effort is needed to create the objects that I want.

### Use the tool as is

PowerShell is a great shell, it can execute any executable, the same way that any good shell can do.
No change is needed, just run `kubectl` and you're done!

#### Issues with simple execution

If I want the native application just running the executable is not the only criteria for fully participating in the PowerShell environment.
Tab-completion for parameters and auto-generated values for parameters is something that PowerShell users have come to expect.
For most native executables, there are tab-completers for most shells (bash/zsh)
More importantly, is the _object_ pipeline which is one of the places that PowerShell brings so much, well, power.
The ability to not have to use `cut`, `sed`, `awk`, etc. but to treat the results _logically_ is extremely compelling.

In the next post, I'll go through a couple possible approaches for taking advantage of all these native tools.
And I'll investigate whether there's a way to automatically use the help for the native utility to generate cmdlets
and convert output to objects that participate in the PowerShell pipeline.

James Truher
Software Engineer
PowerShell Team

___

## Native Commands in PowerShell - A New Approach - Part 2

In the last post I went through some some strategies for executing native executable and having them
participate more fully in the PowerShell environment.
In this post, I'll be going through a couple of experiments I've done with the kubernetes `kubectl` utility.

## Is there a better way

It may be possible to create a framework that inspects the help of the application and _automatically_ creates the code that calls the underlying application.
This framework can also handle the output mapping to an object more suitable for the PowerShell environment.

## Possibilities in wrapping

The aspect that makes this possible is that some commands have consistently structured help that describes how the application can be used.
If this is the case, then we can iteratively call the help, parse it,
and automatically construct much of the infrastructure needed to allow these native applications to be incorporated into the PowerShell environment.

### First Experiment - Microsoft.PowerShell.Kubectl Module

I created a wrapper for to take the output of `kubectl api-resources` and create functions for each returned resource.
This way, instead of running `kubectl get pod`; I could run `Get-KubectlPod` (a much more _PowerShell-like_ experience).
I also wanted to have the function return objects that I could then use with other PowerShell tools (Where-Object, ForEach-Object, etc).
To do this, I needed a way to map the output (JSON) of the `kubectl` tool to PowerShell objects.
I decided that it was reasonable to use a more declarative approach that maps the property in the JSON to a PowerShell class member.

There were some problems that I wanted to solve with this first experiment

- wrap `kubectl api-resources` in a function
  - automatically create object output from `kubectl api-resources`
- Auto-generate functions for each resource that could be retrieved (only resource get for now)
  - only support `name` as a parameter
- Auto-generate the conversion of output to objects to look similar to the usual `kubectl` output

When it came to wrapping `kubectl api-resources` I took the static approach rather than auto generation.
First, because it was my first attempt so I was still finding my feet.
Second, because this is one of the `kubectl` commands that does not emit JSON.
So, I took the path of parsing the output of `kubectl api-resources -o wide`.
My concern is that I wasn't sure whether the table changes width based on the screen width.
I calculated column positions based on the fields I knew to be present and then parsed the line using the offsets.
You can see the code in the function `get-kuberesource` and the constructor for the PowerShell class `KubeResource`.
My plan was that these resources would drive the auto-generation of the Kubernetes resource functions.

Now that I have retrieved the resources, I can auto-generate specific resource function for calling the `kubectl get <resource>`.
At the time, I wanted some flexibility in the creation of these proxy functions,
so I provided a way to include a specific implementation, if desired (see the `$proxyFunctions` hashtable).
I'm not sure that's needed now, but we'll get to that later.
The problem is that while the resource data can be returned as JSON, that JSON has absolutely no relation to the way the
data is represented in the `kubectl get pod` table.
Of course, in PowerShell we can create formatting to present any member of an object (JSON or otherwise),
but I like to be sure that the properties seen in a table are properties that I can use with `Where-Object`, etc.
Since, I want to return the data as objects, I created classes for a couple resources by hand but thought there might be a better way.

I determined that when you get data from kubernetes, the table (both normal and wide) output _is created on the server_.
This means the mapping of the properties of the JSON object to the table columns is defined in the server code.
It's possible to provide data as custom columns, but you need to provide the value for the column using a JSON path expression.
So, it's not possible to automatically generate those tables.
However, I thought it might be possible to provide a configuration file that could be read to automatically generate a PowerShell class.
The configuration file would need to define the mapping between the property in the table with the properties of the object
The file would include the name of the column and the expression to get the value for the object.
h allows a user to retrieve the JSON object and construct their custom object without touching the programming logic
of the module but a configuration file.
I created the `ResourceConfiguration.json` file to encapsulate all the resources that I had access to and provide a way to customize
the object members where desired.

here's an example:

```json
  {
    "TypeName": "namespaces",
    "Fields": [
      {
        "PropertyName": "NAME",
        "PropertyReference": "$o.metadata.NAME"
      },
      {
        "PropertyName": "STATUS",
        "PropertyReference": "$o.status.phase"
      },
      {
        "PropertyName": "AGE",
        "PropertyReference": "$o.metadata.creationTimeStamp"
      }
    ]
  },
```

This JSON is converted into a PowerShell class whose constructor takes the JSON object and assigns the values to the members,
according to the `PropertyReference`.
The module automatically attaches the original JSON to a hidden member `originalObject` so if you want to inspect
all the data that's available, you can.
The module also automatically generates a proxy function so you can get the data:

```powershell
function Get-KubeNamespace
{
  [CmdletBinding()]
  param ()
  (Invoke-KubeCtl -Verb get -resource namespaces).Foreach({[namespaces]::new($_)})
}
```

This function is then exported so it's available in the module.
When used, it behaves very close to the original:

```powershell
PS> Get-KubeNamespace

Name                 Status Age
----                 ------ ---
default              Active 5/6/2020 6:13:07 PM
default-mem-example  Active 5/14/2020 8:14:45 PM
docker               Active 5/6/2020 6:14:25 PM
kube-node-lease      Active 5/6/2020 6:13:05 PM
kube-public          Active 5/6/2020 6:13:05 PM
kube-system          Active 5/6/2020 6:13:05 PM
kubernetes-dashboard Active 5/18/2020 8:44:01 PM
openfaas             Active 5/6/2020 6:51:22 PM
openfaas-fn          Active 5/6/2020 6:51:22 PM

PS> kubectl get namespaces --all-namespaces

NAME                   STATUS   AGE
default                Active   26d
default-mem-example    Active   18d
docker                 Active   26d
kube-node-lease        Active   26d
kube-public            Active   26d
kube-system            Active   26d
kubernetes-dashboard   Active   14d
openfaas               Active   26d
openfaas-fn            Active   26d
```

but importantly, I can use the output with `Where-Object` and `ForEach-Object` or change the format to list, etc.

```powershell
PS> Get-KubeNamespace |? name -match "faas"

Name        Status Age
----        ------ ---
openfaas    Active 5/6/2020 6:51:22 PM
openfaas-fn Active 5/6/2020 6:51:22 PM
```

### Second Experiment - Module KubectlHelpParser

I wanted to see if I could read any help content from `kubectl` that would enable me to auto-generate a complete
proxy of the `kubectl` command that included general parameters, command specific parameters, and help.
It turns out that `kubectl` help is regular enough that this is quite possible.

When retrieving help, kubectl provides subcommands that also have structured help.
I created a recursive parser that allowed me to retrieve all of the help for all of the available kubectl commands.
This means that if an additional command is provided in the future, and the help for that command follows the
existing pattern for help, this parser will be able to generate a command for it.

```powershell
PS> kubectl --help
kubectl controls the Kubernetes cluster manager.

 Find more information at: https://kubernetes.io/docs/reference/kubectl/overview/

Basic Commands (Beginner):
  create         Create a resource from a file or from stdin.
  expose         Take a replication controller, service, deployment or pod and expose it as a new Kubernetes Service
  run            Run a particular image on the cluster
  set            Set specific features on objects

Basic Commands (Intermediate):
  explain        Documentation of resources
  get            Display one or many resources
. . .

kubectl set --help

PS> kubectl set --help

Configure application resources

 These commands help you make changes to existing application resources.

Available Commands:
  env            Update environment variables on a pod template
  . . .
  subject        Update User, Group or ServiceAccount in a RoleBinding/ClusterRoleBinding

Usage:
  kubectl set SUBCOMMAND [options]

PS> kubectl set env --help

Update environment variables on a pod template.

 List environment variable definitions in one or more pods, pod templates. Add, update, or remove container environment
variable definitions in one or more pod templates (within replication controllers or deployment configurations). View or
modify the environment variable definitions on all containers in the specified pods or pod templates, or just those that
match a wildcard.

 If "--env -" is passed, environment variables can be read from STDIN using the standard env syntax.

 Possible resources include (case insensitive):

  pod (po), replicationcontroller (rc), deployment (deploy), daemonset (ds), job, replicaset (rs)

Examples:
  # Update deployment 'registry' with a new environment variable
  kubectl set env deployment/registry STORAGE_DIR=/local
  . . .
  # Set some of the local shell environment into a deployment config on the server
  env | grep RAILS_ | kubectl set env -e - deployment/registry

Options:
      --all=false: If true, select all resources in the namespace of the specified resource types
      --allow-missing-template-keys=true: If true, ignore any errors in templates when a field or map key is missing in
the template. Only applies to golang and jsonpath output formats.
  . . .
      --template='': Template string or path to template file to use when -o=go-template, -o=go-template-file. The
template format is golang templates [http://golang.org/pkg/text/template/#pkg-overview].

Usage:
  kubectl set env RESOURCE/NAME KEY_1=VAL_1 ... KEY_N=VAL_N [options]

Use "kubectl options" for a list of global command-line options (applies to all commands).
```

The main function of the module will recursively collect the help for all of the commands and construct an
object representation that I hope can then be used to generate the proxy functions.
This is still very much a work in progress, but it is definitely showing promise.
Here's an example of what it can already do.

```powershell
PS> import-module ./khp2.psm1
PS> $res = get-kubecommands
PS> $res.subcommands[3].subcommands[0]
```

```output
Command             : set env
CommandElements     : {, set, env}
Description         : Update environment variables on a pod template.

                       List environment variable definitions in one or more pods, pod templates. Add, update, or remove container environment variable definitions in one or more pod templates (within replication controllers or deployment configurations). View or modify the environment variable definitions
                      on all containers in the specified pods or pod templates, or just those that match a wildcard.

                       If "--env -" is passed, environment variables can be read from STDIN using the standard env syntax.

                       Possible resources include (case insensitive):

                        pod (po), replicationcontroller (rc), deployment (deploy), daemonset (ds), job, replicaset (rs)
Usage               : kubectl set env RESOURCE/NAME KEY_1=VAL_1 ... KEY_N=VAL_N [options]
SubCommands         : {}
Parameters          : {[Parameter(Mandatory=$False)][switch]${All}, [Parameter(Mandatory=$False)][switch]${NoAllowMissingTemplateKeys}, [Parameter(Mandatory=$False)][System.String]${Containers} = "*", [Parameter(Mandatory=$False)][switch]${WhatIf}…}
MandatoryParameters : {}
Examples            : {kubectl set env deployment/registry STORAGE_DIR=/local, kubectl set env deployment/sample-build --list, kubectl set env pods --all --list, kubectl set env deployment/sample-build STORAGE_DIR=/data -o yaml…}
```

```powershell
PS> $res.subcommands[3].subcommands[0].usage
```

```output
Usage                                                               supportsFlags hasOptions
-----                                                               ------------- ----------
kubectl set env RESOURCE/NAME KEY_1=VAL_1 ... KEY_N=VAL_N [options]         False       True
```

```powershell
PS> $res.subcommands[3].subcommands[0].examples
```

```output
Description                                                   Command
-----------                                                   -------
Update deployment 'registry' with a new environment variable  kubectl set env deployment/registry STORAGE_DIR=/local
. . .

```

```powershell
PS> $res.subcommands[3].subcommands[0].parameters.Foreach({$_.tostring()})
```

```output

[Parameter(Mandatory=$False)][switch]${All}
[Parameter(Mandatory=$False)][switch]${NoAllowMissingTemplateKeys}
[Parameter(Mandatory=$False)][System.String]${Containers} = "*"
[Parameter(Mandatory=$False)][switch]${WhatIf}
. . .
[Parameter(Mandatory=$False)][System.String]${Selector}
[Parameter(Mandatory=$False)][System.String]${Template}

```

There are still a lot of open questions and details to work out here:

- how are mandatory parameters determined?
- how do we keep a map of used parameters?
- does parameter order matter?
- can reasonable debugging be provided?
- do we have to "boil the ocean" to provide something useful?

I believe it may be possible to create a more generic framework which would allow a larger number native executables to be
more fully incorporated into the PowerShell ecosystem.
These are just the first steps in the investigation, but it looks very promising.

## Call To Action

First, I'm really interested in knowing that having a framework that can auto-generate functions that wrap a native executable is useful.
The obvious response might be "of course", but how much of a solution is really needed to provide value?
Second, I would _really_ like to know if you would like us to investigate _specific_ tools for this sort of treatment.
If it is possible to make this a generic framework, I would love to have more examples of tools which would be beneficial
to you and test our ability to handle.

James Truher
Software Engineer
PowerShell Team

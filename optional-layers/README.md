# AWS SAM Optional Layers Experiment

The purpose of this repository is to outline a means by which one can decide whether or not to use
layers as part of a deployment.

## The problem

Suppose that during development, you have access to AWS Lambda Layers, but during production, you do
not. It would be nice to have the option to use layers as part of the development phase, but then be
able to effortlessly disable layers during production.

## The solution

Use CloudFormation templating with parameters to switch between a with-layers approach and a
without-layers approach.

### The lambdas

This repository contains two lambda functions: [hello_world](hello_world/app.py) and
[foo_bar](foo_bar/app.py). Each of these lambdas has the same requirements, and so it would be nice
to package their dependencies separately to reduce redundancies during deployment, save bandwidth,
save S3 disk space, etc.

### The requirements file

We maintain a single [`requirements.txt`](deps/requirements.txt) file and create symlinks to this
file within each lambda function to keep them synchronized.

### The template file

As part of the deployment, we maintain a template that defines an additional parameter named
`DeployWithLayers`.

```yaml
Parameters:
  DeployWithLayers:
    Description: Whether or not to deploy the stack using layers.
    Type: String
    Default: 'No'
    AllowedValues:
      - 'Yes'
      - 'No'
```

This parameter controls whether we should deploy the stack using layers or not, and is converted
into a *condition* named `UseLayers`.

```yaml
Conditions:
  UseLayers: !Equals [ !Ref DeployWithLayers, 'Yes' ]
```

This condition allows us to choose whether or not to use layers as part of the deployment. It is
used throughout the template file to control which resources to build and deploy. For example,
we use it to control whether to build the actual `SharedLayer` resource:

```yaml
Resources:
  SharedLayer:
    Condition: UseLayers
```

Additionally, we define a global usage of layering to determine whether or no to use the layer in
our lambda functions:

```yaml
Globals:
  Function:
    Layers: !If [ UseLayers, [ !Ref SharedLayer ], [ ] ]
```

Lastly, we use this condition to switch between whether to use the `python3.12` and `makefile`
workflows for each lambda. This is necessary to avoid accidentally packaging the dependencies with
each lambda at the same time we use layers, as would be the case were we to continue using the
`python3.12` workflow when `DeployWithLayers=Yes` (i.e. `UseLayers=true`). This would nullify the
whole purpose of using layers in the first place.

```yaml
Resources:
  HelloWorldFunction:
    Metadata:
      BuildMethod: !If [ UseLayers, makefile, python3.12 ]
```

### The makefile

When using layers, we package the lambda using a [custom Makefile](layers.makefile). This, however,
requires us to provide a Makefile to each lambda function, which is responsible for copying the
lambda artifacts into the correct place. Fortunately, we can simply define a catch-all target named
`build-%` to satisfy this need. We symlink `layers.makefile` into each lambda's `CodeUri` to ensure
that each lambda is built identically.

Should the need arise to build an individual lambda in a unique way, we can either add that target
to the global Makefile with the appropriate name: `build-HelloWorldFunction`, for example. As long
as that target is defined *before* the catch-all `build-%` target, we can handle unique
circumstances.

For example:

```make
build-HelloWorldFunction:
	# do something special

build-%:
	mkdir -p "$(ARTIFACTS_DIR)"
	cp -r * "$(ARTIFACTS_DIR)"
```

## Building

Now that we've set everything up, it's time to deploy the stack in both ways.

### Using Layers

By default, `DeployWithLayers` is set to `"No"`, and so we must do something *extra* to trigger the
build with layers. This is fairly straightforward:

    sam build --parameter-overrides DeployWithLayers=Yes

This will create the `.aws-sam/` directory where the build artifacts are stored. Within the
`.aws-sam/build` directory, you should see distinct directories for the `SharedLayer`, as well as
the `HelloWorldFunction` and `FooBarFunction` lambdas. Inspecting these layers, you should notice
that the function directories simply contain the contents of their respective source directories.
In other words, there should be an `app.py`, `Makefile`, and `requirements.txt`.

Once things are built, we are ready to deploy:

    sam deploy --stack-name optional-layers --parameter-overrides DeployWithLayers=Yes

#### An issue with `sam sync`

Unfortunately, it does not appear that running `sam sync --watch` works correctly with this method,
as it doesn't maintain the connection between the nested layer created by the sync and the actual
shared layer. To fix this, we simply need to add the `--no-dependency-layer` flag to the `sam sync`
command:

    sam sync --stack-name optional-layers --no-dependency-layer --parameter-overrides DeployWithLayers=Yes --watch

### Without Layers

As mentioned above, `DeployWithLayers` defaults to `No`, and so in order to deploy without layers,
simply run the `sam build`, `sam deploy`, and `sam sync` commands as usual.

Note that when building without layers, the `SharedLayer` is still built. This appears to be
something which cannot be controlled with the `Condition` argument. It doesn't appear to cause
problems, except that it does add an additional artifact to the S3 bucket, a small price to pay for
the flexibility that layers offer.

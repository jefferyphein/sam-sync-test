# AWS SAM Sync Experiment

The purpose of this repository is to outline a somewhat "easy" way to be able to make modifications
to AWS Lambda functions as well as upstream dependencies in a way that is compatible with `sam local
invoke` as well as `sam sync --watch`.

## The problem

When making upstream changes to a lambda, you need to update the layer associated to the upstream
dependencies for the lambda. This is often done by adding the changes to a zip file and pushing that
zip file to AWS. This can be cumbersome and time consuming.

When upstream packages are maintained by you or your organization, however, making changes and
"compiling" those changes into a zip file can be slow, tedious, and annoying.

## The solution

For Python projects, we will take advantage of [editable
installs](https://setuptools.pypa.io/en/latest/userguide/development_mode.html) to take advantage of
their ability to make local changes without needing to either rebuild the source distribution or
re-run `pip install`.

However, it does not appear that this approach works natively with AWS Lambda, and so we'll need a
couple simple workarounds to get things up and running.

### The makefile

First thing to note is that we'll use the "makefile" build method. This requires updating the
[template file](templates.yaml) and adding the following lines to your lambda, which we've named
"HelloWorldFunction" for the sake of this project:

```yaml
Resources:
  HelloWorldFunction:
    Metadata:
      BuildMethod: makefile
```

Additionally, we must place a [Makefile](hello_world/Makefile) within the lambda's directory with a
target named `build-HelloWorldFunction`.

Following the [AWS tutorial for makefiles](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/building-custom-runtimes.html),
we will make some minor modifications to address some quirks of working with editable installs.

### The requirements file

For each dependency your lambda has, you will typically add a line within your requirements
file like the following:

    my-dependency==1.2.3
    my-other-dependency=3.2.1

However, if we *own* those dependencies and want to make *live* modifications to them, this approach
does not work very well.

### Editable installs

Instead of working with requirements of the form `my-dependency==1.2.3` during the development
phase, we will instead use editable installs and *temporarily* update our requirements file to
redirect to our local changes. This requires two steps:

1. Clone the dependency's project into the lambda's root directory.

2. Update the requirements file replacing the `my-dependency==1.2.3` line with

    ```
    -e ./my-dependency/path/to/setup/directory
    ```

In our example, we have already "cloned" the upstream dependency into [the
`hello_world/sam-sync-test-upstream` directory](hello_world/sam-sync-test-upstream). We've also
modified the [requirements file](hello_world/requirements.txt) to point to the appropriate directory
where `pip install` can be run.

### Some initial issues

In an ideal world, this would *Just Work*, however, due to how `sam` works, without some extra
modifications to the [makefile](hello_world/Makefile). If we simply just run `pip install`, what
happens is that our cloned upstream repository is copied into a `/tmp` directory, then the edit
symlink artifacts that gets placed in your `site-packages` directory will contain a path that
looks like `/tmp/tmpxyz.../my-dependency/src`. This is a problem!

To address this, as part of the build, we will mangle that path to point to the correct location
within the container where the lambda will be run, `/var/task`. We do this by adding the following
line to our makefile:

    find $(ARTIFACTS_DIR) -type f -name '__editable__.*.pth' -exec sed -i 's|/tmp/[^/]*/|/var/task/|g' {} \;

This will edit each `__editable__.*.pth` file in-place, replacing the `/tmp/tmp.../` with
`/var/task/`. This ensures that the editable path can be found within the container.

This is not quite enough though, because we've now copied the upstream code we want to modify into
the artifacts directory, and so we still would need to run `sam build` every time we modify the
upstream dependency.

To address this, we will additionally *delete* the copied upstream package directory within our
artifacts directory and replace it with an identical symbolic link that points to the actual cloned
directory within our lambda directory. This requires adding the following lines to your makefile:

    rm -rf $(ARTIFACTS_DIR)/<my-dependency-name>
    ln -s /path/to/lambda/directory/<my-dependency-name> $(ARTIFACTS_DIR)/<my-depenency-name>

For the sake of this example, the path to the lambda directory is where I've cloned my lambda's git
repository: `/home/jeff/src/sam-sync-test/hello_world` and the name of the dependency is
`sam-sync-test-upstream`. My [personal Makefile](hello_world/Makefile) reflects these values. Your
own implementation will differ slightly.

Now we are all set up!

## Building

With all of this set up, we can now run `sam build` and it will update our editable symlinks, as
well as redirect things to the correct place.

You should now see the output of `pip install` followed by "Build Succeeded" in your terminal.

## Local invocation

Running `sam local invoke` should now also work correctly. At this point, you can make modifications
to either your lambda function or its upstream dependencies and see those changes reflected in the
output of this command.

## Remote synchronization

You can also now run `sam sync --watch` and watch your changes get pushed to AWS for both your
lambda as well as any upstream dependencies you've configured using this method.

What makes this work is the fact that the upstream source code has been cloned into the directory
being watched by `sam sync` in combination with the additional commands included in the makefile
to both update the editable links as well as symlink the upstream artifacts directory to the actual
source code.

When any of the files located in your lambda directory are modified, the `build-HelloWorldFunction`
build target is run, setting things up for you automatically.

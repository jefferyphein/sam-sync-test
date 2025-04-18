# AWS SAM Sync Experiment

The purpose of this repository is to outline an "easy"--but kinda hacky--way to be able to make
modifications to AWS Lambda functions as well as its upstream dependencies in a way that is
compatible with `sam local invoke` as well as `sam sync --watch`.

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
[template file](template.yaml) and adding the following lines to your lambda, which we've named
"HelloWorldFunction" for the sake of this project:

```yaml
Resources:
  HelloWorldFunction:
    Metadata:
      BuildMethod: makefile
```

Additionally, we must place a [Makefile](hello_world/Makefile) within the lambda's directory with a
target named `build-HelloWorldFunction`.

Following the [AWS tutorial for
makefiles](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/building-custom-runtimes.html),
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

In an ideal world, this would *Just Work*, however, due to how `sam` works, we need to make some
extra modifications to the [makefile](hello_world/Makefile). If we simply just run `pip install`,
what happens is that our cloned upstream repository is copied into a `/tmp` directory, then the
editable symlink artifacts that gets placed in your `site-packages` directory will contain a path
that looks like `/tmp/tmpxyz.../my-dependency/src`. This is a problem!

To address this, we'll mangle the temporary path so that it points to the correct location *within
the container* as an epilogue to the `pip install`. The lambda and all of its dependendies will be
located within the `/var/task` inside of the container, and so we will start by modifying the
appropriate symlinks as follows within our makefile:

    find $(ARTIFACTS_DIR) -type f -name '__editable__.*.pth' -exec sed -i 's|/tmp/tmp[^/]*/|/var/task/|g' {} \;

This will edit each `__editable__.*.pth` file in-place, replacing the `/tmp/tmp.../` with
`/var/task/`. These files are placed within our `site-packages` directory by `setuptools` as part
of an editable installation. These files simply contain a directory where the code is located.
This ensures that the editable path can be found within the container.

This is not quite enough though, because the upstream code wasn't copied into the artifacts
directory, and so we won't be able to find the upstream code inside of the container.

To address this, we'll also create a symlink that points to the cloned repository within our lambda
directory. To do this, add the following line to your makefile:

    ln -s /path/to/lambda/directory/<my-dependency-name> $(ARTIFACTS_DIR)/<my-depenency-name>

For the sake of this example, the path to the lambda directory is where I've cloned my lambda's git
repository: `/home/jeff/src/sam-sync-test/hello_world` and the name of the dependency is
`sam-sync-test-upstream`. My [personal Makefile](hello_world/Makefile) reflects these values. Your
own implementation will differ slightly.

Now we are all set up! We should be able to make modifications to the upstream dependencies.

## Building

With all of this set up, we can now run `sam build` and it will update our editable symlinks, as
well as redirect our upstream dependencies to the correct place.

You should now see the output of `pip install` followed by "Build Succeeded" in your terminal.

### Local invocation

Running `sam local invoke` should now also work correctly. At this point, you can make modifications
to the upstream dependency and see those changes immediately reflected when running this command
again.

To verify this is working correctly, you should output that looks similar to the following:

    Mounting resolved symlink (/path/to/sam-sync-test/.aws-sam/build/HelloWorldFunction/sam-sync-test-upstream -> /path/to/sam-sync-test/hello_world/sam-sync-test-upstream) as /var/task/sam-sync-test-upstream:ro,delegated, inside runtime container

This provides an explicit indication that the symlink we created has been correctly mounted into the
runtime container.

Note that it is no longer necessary to run `sam build` when updating upstream dependencies! However,
it must be run when updating the lambda itself. By also creating symlinks for the lambda in a similar
manner, we can edit both the lambda and upstream dependencies without the need to run `sam build`
repeatedly.

### Remote synchronization

You can now also run `sam sync --watch` and observe as your local changes to your lambda directory
get pushed to AWS for both your lambda as well as any upstream dependencies you've configured using
this method.

Note that when any of the files located in your lambda directory are now modified, the
`build-HelloWorldFunction` build target will be run locally, then synchronize with AWS. This can
get costly if making a lot of minor updates, so be mindful.

What makes this work is the fact that the upstream source code has been cloned into the directory
being watched by `sam sync` in combination with the additional commands included in the makefile
to both update the editable links as well as symlink the upstream package to its actual source.

## Finishing Up

Once you're done developing, make sure to restore both the makefile and the requirements file to
their original state.

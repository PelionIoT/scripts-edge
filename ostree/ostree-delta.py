#!/usr/bin/env python3

# Copyright (c) 2021, Pelion Limited and affiliates.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Script to create a static delta between 2 ostree repos."""

import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import warnings
import tarfile


def warning_on_one_line(
    message, category, filename, lineno, file=None, line=None
):
    """Format a warning the standard way."""
    return "{}:{}: {}: {}\n".format(
        filename, lineno, category.__name__, message
    )


def warning(message):
    """
    Issue a UserWarning Warning.

    Args:
    * message: warning's message

    """
    warnings.warn(message, stacklevel=2)
    sys.stderr.flush()


def _execute_command(command, timeout=None):

    print(command)
    p = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=-1,
        universal_newlines=True,
    )
    try:
        output, error = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        ExecuteHelper._print("Timed out after {}s".format(timeout))
        p.kill()
        output, error = p.communicate()

    print(error)

    return output


def _determine_machine_from_repo(repo):

    # Get the refs from the repo, and discard the ones that start "ostree".
    # This is so we can auto-detect the machine tyoe from the repo, which
    # is important for when the repo comes from a compile wic file.

    command = ["ostree", "--repo={}".format(repo), "refs"]
    output = _execute_command(command).rstrip().splitlines()

    machine = None

    # Search through the refs and remove any elements that start with "ostree"
    for ref in output:
        if ref.startswith("ostree"):
            output.remove(ref)

    # There should only be one ref remaining - the machine name. Anything else
    # is an error.
    if len(output) == 1:
        machine = output[0]
    else:
        print("Error:\tCould not determine the machine name from the repo")
        print("\tPossible values are:")
        for ref in output:
            print("\t\t{}".format(ref))
    return machine


def _get_data_from_repo(repo, machine, data):
    # Get the data from the repo

    values = []

    command = ["ostree", "--repo={}".format(repo), "log", machine]
    output = _execute_command(command).rstrip().splitlines()
    for line in output:

        if line.startswith(data):
            # Date variable requires specific parsing since it contains
            # spaces and colons
            if data == "Date":
                values.append(line.split(":", 1)[1].strip())
            else:
                values.append(line.split()[1])
    if len(values) > 0:
        return values
    else:
        return None


def _get_shas_from_repo(repo, machine):
    # Get the sha from the repo
    return _get_data_from_repo(repo, machine, "commit")


def _get_version_from_repo(repo, machine):
    # Get the version from the repo
    return _get_data_from_repo(repo, machine, "Version")


def _rev_parse_in_repo(repo, rev):
    # Get the sha from the repo
    if rev is None:
        return None

    command = ["ostree", "--repo={}".format(repo), "rev-parse", rev]
    output = _execute_command(command).rstrip().splitlines()
    try:
        return output[0]
    except IndexError:
        return None


def _get_date_from_repo(repo, machine):
    # Get the date from the repo
    return _get_data_from_repo(repo, machine, "Date")


def _generate_metadata(outputpath, from_sha, to_sha):
    # Save the from and to shas into a file.  # They will be needed on the
    # device at the deploy stage.
    with open(os.path.join(outputpath, "metadata"), "w") as metafile:
        metafile.write("From-sha:{}\n".format(from_sha))
        metafile.write("To-sha:{}\n".format(to_sha))


def _generate_tarball(outputpath):

    command = [
        "tar",
        "-cf",
        "{}/data.tar".format(outputpath),
        "--directory",
        outputpath,
        "--exclude=./data.tar",
        ".",
    ]
    output = _execute_command(command)
    print(output)

    command = ["gzip", "--force", "{}/data.tar".format(outputpath)]
    output = _execute_command(command)
    print(output)


def _transfer_sha_between_repos(
    source_repo, dest_repo, sha
):
    """
    Transfer a SHA from one repo to another

    Args:
    * source_repo (Path)
    * dest_repo   (Path) 
    * sha,

    """
    command = [
        "ostree",
        "--repo={}".format(dest_repo),
        "pull-local",
        "{}".format(source_repo),
        sha,
    ]
    output = _execute_command(command)
    print(output)


def _generate_static_delta_between_shas(
    repo, outputpath, machine, to_sha, from_sha
):
    """
    Generate the static delta information.

    Args:
    * repo        (Path): Initial (deployed) repository.
    * outputpath  (Path): output folder.
    * machine,
    * to_sha,
    * from_sha,   Optionally None to use --empty option
    """
    if from_sha is None:
        # set the metadata from_sha to be the machine name. The deploy script on the device
        # will sanity check that the machine is present in the device repo.
        _generate_metadata(outputpath, machine, to_sha)
    else:
        _generate_metadata(outputpath, from_sha, to_sha)

    output_filename = os.path.join(outputpath, "superblock")

    # Generate the static delta.
    # the max-chunk-size gives the delta in a single data file, called 0
    command = [
        "ostree",
        "--repo={}".format(repo),
        "static-delta",
        "generate",
        "--max-chunk-size=2048",
        "--min-fallback-size=0",
        "--filename={}".format(output_filename),
        "--to",
        to_sha,
    ]
    if from_sha is None:
        command += [
            "--empty",
        ]
    else:
        command += [
            "--from",
            from_sha
        ]

    output = _execute_command(command)
    print(output)

    # Create a tarball.
    _generate_tarball(outputpath)


def _str_to_resolved_path(path_str):
    """
    Convert a string to a resolved Path object.

    Args:
    * path_str (str): string to convert to a Path object.

    """
    return pathlib.Path(path_str).resolve(strict=False)


def ensure_is_directory(path):
    """
    Check that a file exists and is a directory.

    Raises an exception on failure and does nothing on success

    Args:
    * path (PathLike): path to check.

    """
    path = pathlib.Path(path)
    if not path.exists():
        raise ValueError('"{}" does not exist'.format(path))
    if not path.is_dir():
        raise ValueError('"{}" is not a directory'.format(path))


def _parse_args():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--repo",
        metavar="DIR",
        type=_str_to_resolved_path,
        help="Initial (deployed) repo.",
        required=True,
    )

    parser.add_argument(
        "--output",
        metavar="DIR",
        type=_str_to_resolved_path,
        help="Output Folder. Will be created if necessary.",
        required=True,
    )

    parser.add_argument(
        "--update_repo",
        metavar="DIR",
        type=_str_to_resolved_path,
        help="New (update) repo.",
        required=False,
    )

    parser.add_argument(
        "--machine",
        type=str,
        help="Machine (and therfore ref) being worked on",
        required=False,
    )

    parser.add_argument(
        "--to_sha",
        type=str,
        help="sha of the tip of the delta image",
        required=False,
    )

    parser.add_argument(
        "--from_sha",
        type=str,
        help="sha of the base of the delta image",
        required=False,
    )

    parser.add_argument(
        "--generate_bin",
        action="store_true",
        help="Create a .bin file instead of .tar.gz",
        default=False,
        required=False,
    )

    parser.add_argument(
        "--empty",
        action="store_true",
        help="Create a clean static delta.",
        default=False,
        required=False,
    )

    args, unknown = parser.parse_known_args()

    if len(unknown) > 0:
        warning("unsupported arguments: {}".format(unknown))

    ensure_is_directory(args.repo)

    return args


def main():
    """Script entry point."""
    warnings.formatwarning = warning_on_one_line

    args = _parse_args()

    os.makedirs(args.output, exist_ok=True)

    repo = args.repo
    if args.machine is None:
        machine = _determine_machine_from_repo(repo)
    else:
        machine = args.machine

    if machine is None:
        sys.exit(2)

    if args.update_repo is None:
        update_repo = repo
    else:
        update_repo = args.update_repo

    if args.to_sha is None:
        to_rev = machine
    else:
        to_rev = args.to_sha

    if args.empty:
        from_rev = None
    else:
        # from_sha defaults to previous commit on machine's branch if single repo,
        # else latest commit on machine's branch in original repo
        if args.from_sha is None:
            if repo == update_repo:
                from_rev = machine + "^"
            else:
                from_rev = machine
        else:
            from_rev = args.from_sha

    to_sha = _rev_parse_in_repo(update_repo, to_rev)
    if to_sha is None:
        warning(
            "rev {} not found in {}".format(
                to_rev, update_repo
            )
        )
        exit(1)

    from_sha = _rev_parse_in_repo(repo, from_rev)
    if from_sha is None and from_rev is not None:
        warning(
            "rev {} not found in {}".format(
                from_rev, repo
            )
        )
        exit(1)

    if repo != update_repo:
        _transfer_sha_between_repos(
            source_repo=update_repo,
            dest_repo=repo,
            sha=to_sha,
        )

    _generate_static_delta_between_shas(
        repo=repo,
        outputpath=args.output,
        machine=machine,
        to_sha=to_sha,
        from_sha=from_sha,
    )

    if args.generate_bin:
        # Rename the tar-gz file to .bin to avoid a "feature" with manifest
        # generation.
        command = [
            "mv",
            "{}/data.tar.gz".format(args.output),
            "{}/data.bin".format(args.output),
        ]
        output = _execute_command(command)
        print(output)


if __name__ == "__main__":
    sys.exit(main())

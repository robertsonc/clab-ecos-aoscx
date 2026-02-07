#!/usr/bin/env python3
# Copyright 2024 Aruba Networks / HPE
# Adapted for vrnetlab by community contributors
#
# Aruba Virtual Gateway (VGW) vrnetlab launcher
#
# TODO: This is a skeleton based on the EdgeConnect ECOS launcher.
# Boot detection, NIC mapping, and initial configuration will need
# to be updated once the VGW image behavior is understood.

import logging
import os
import re
import signal
import socket
import sys
import time

import vrnetlab


def handle_SIGCHLD(signal, frame):
    os.waitpid(-1, os.WNOHANG)


def handle_SIGTERM(signal, frame):
    sys.exit(0)


signal.signal(signal.SIGINT, handle_SIGTERM)
signal.signal(signal.SIGTERM, handle_SIGTERM)
signal.signal(signal.SIGCHLD, handle_SIGCHLD)

TRACE_LEVEL_NUM = 9
logging.addLevelName(TRACE_LEVEL_NUM, "TRACE")


def trace(self, message, *args, **kws):
    if self.isEnabledFor(TRACE_LEVEL_NUM):
        self._log(TRACE_LEVEL_NUM, message, args, **kws)


logging.Logger.trace = trace


class VGW_vm(vrnetlab.VM):
    """Aruba Virtual Gateway VM"""

    def __init__(self, hostname, username, password, conn_mode):
        # Find the qcow2 disk image
        for e in os.listdir("/"):
            if re.search(r"\.qcow2$", e):
                disk_image = "/" + e
                break
        else:
            raise Exception("No qcow2 disk image found")

        # TODO: Confirm RAM requirements for VGW
        super(VGW_vm, self).__init__(
            username, password, disk_image=disk_image, ram=4096
        )
        self.hostname = hostname
        self.conn_mode = conn_mode
        # TODO: Confirm NIC count and roles for VGW
        self.num_nics = 6
        self.nic_type = "virtio-net-pci"
        self.initial_config_applied = False
        self.reboot_pending = False

    def bootstrap_spin(self):
        """Monitor boot progress and wait for system ready"""
        if self.spins > 300:
            # 5 minutes timeout
            self.logger.warning("Bootstrap timeout - proceeding anyway")
            self.running = True
            return

        # TODO: Update expected boot strings once VGW boot sequence is known
        (ridx, match, res) = self.tn.expect(
            [
                b"Appliance Manager is at",                       # 0 - Ready with IP
                b"Press F1 to start Command Line Interface",      # 1 - Console menu
                b"login:",                                        # 2 - Login prompt
                b"Silver Peak",                                   # 3 - Boot banner
                b"ECOS version",                                  # 4 - Version banner
            ],
            1,
        )

        # Log console output for debugging
        if res:
            res_text = res.decode(errors='replace').strip()
            if res_text and len(res_text) > 2:
                self.logger.info(f"Console: {res_text[-500:]}")

        if ridx == 0:
            # Appliance Manager is ready with IP
            self.logger.info("VGW Appliance Manager is accessible")
            if not self.initial_config_applied:
                self._apply_initial_config()
            else:
                self.running = True
            return

        if ridx == 1:
            # Console menu ready
            self.logger.info("VGW console menu ready")

        if ridx == 2:
            # Login prompt - wait for mgmt interface and apply config
            self.logger.info("VGW login prompt detected")
            self._wait_for_mgmt_ip()
            if not self.initial_config_applied:
                self._apply_initial_config()
            else:
                self.running = True
            return

        if ridx == 3:
            # Silver Peak banner - boot in progress
            self.logger.debug("VGW boot in progress...")

        if ridx == 4:
            # Version banner
            self.logger.info("VGW version banner seen")

        # Increment spin counter
        self.spins += 1

    def _wait_for_mgmt_ip(self):
        """Wait for mgmt0 to get DHCP and port 443 to be responsive"""
        self.logger.info("Waiting for management interface to get DHCP...")
        for i in range(60):  # Wait up to 60 seconds
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(2)
                s.connect(('127.0.0.1', 443))
                s.close()
                self.logger.info("Port 443 is responsive - mgmt0 has IP")
                return True
            except (socket.timeout, socket.error):
                time.sleep(1)
        self.logger.warning("Timeout waiting for port 443")
        return False

    def _wait_for_reboot(self):
        """Wait for system to come back up after reload"""
        self.logger.info("Waiting for system to reboot...")

        # First wait for system to go down (connection to drop)
        time.sleep(10)

        # Now wait for it to come back up - poll port 22 or 443
        self.logger.info("Waiting for system to come back online...")
        for i in range(180):  # Wait up to 3 minutes
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.settimeout(2)
                s.connect(('127.0.0.1', 443))
                s.close()
                self.logger.info("System is back online (port 443 responsive)")
                time.sleep(5)  # Give it a few more seconds to stabilize
                return True
            except (socket.timeout, socket.error):
                if i % 10 == 0:
                    self.logger.info(f"  Still waiting for reboot... ({i}s)")
                time.sleep(1)

        self.logger.warning("Timeout waiting for system to come back online")
        return False

    def _apply_initial_config(self):
        """Apply initial configuration via console"""
        if self.initial_config_applied:
            self.running = True
            return

        # TODO: Determine which env vars are relevant for VGW configuration
        admin_password = os.getenv("VGW_ADMIN_PASSWORD", "")
        registration_key = os.getenv("VGW_REGISTRATION_KEY", "")
        account_name = os.getenv("VGW_ACCOUNT_NAME", "")
        site_tag = os.getenv("VGW_SITE_TAG", "ContainerLab")
        portal_hostname = os.getenv("VGW_PORTAL_HOSTNAME", "")

        self.logger.info("Applying initial configuration...")

        def send_cmd(cmd, wait=1):
            self.tn.write(cmd.encode() + b"\r\n")
            time.sleep(wait)

        def wait_for_prompt(prompt, timeout=10):
            self.tn.expect([prompt.encode()], timeout)

        try:
            # Login with default credentials
            self.logger.info("Logging in...")
            send_cmd("admin", 1)
            send_cmd("admin", 2)  # default password

            # Enter enable mode
            self.logger.info("Entering enable mode...")
            send_cmd("enable", 1)
            wait_for_prompt("#", 5)

            # Enter config mode
            self.logger.info("Entering config mode...")
            send_cmd("conf t", 1)
            wait_for_prompt("(config)#", 5)

            # === MAC ADDRESS MAPPING ===
            # TODO: Update interface names and mapping for VGW
            self.logger.info("Applying MAC address mapping...")
            send_cmd("interface mgmt0 mac address eth0", 2)
            send_cmd("interface wan0 mac address eth1", 2)
            send_cmd("interface lan0 mac address eth2", 2)
            send_cmd("interface wan1 mac address eth3", 2)
            send_cmd("interface lan1 mac address eth4", 2)

            # Set hostname
            send_cmd(f'hostname {self.hostname}', 2)

            # Change admin password if provided
            if admin_password:
                send_cmd(f'username admin password {admin_password}', 2)

            # Set portal hostname if provided
            if portal_hostname:
                send_cmd(f'portal hostname {portal_hostname}', 2)

            # Register with cloud portal if credentials provided
            if registration_key and account_name:
                send_cmd(f'system registration "{registration_key}" "{account_name}" {site_tag} {self.hostname}', 3)

            # Exit config mode
            send_cmd("exit", 1)
            wait_for_prompt("#", 5)

            # Write config to memory
            self.logger.info("Writing configuration to memory...")
            send_cmd("write memory", 3)

            self.initial_config_applied = True
            self.logger.info("Initial configuration applied successfully")

            # Reload to apply MAC mapping
            self.logger.info("Reloading system to apply MAC mapping...")
            send_cmd("reload", 2)
            send_cmd("y", 1)

            # Wait for system to come back up
            self._wait_for_reboot()

            self.logger.info("VGW is ready")
            self.running = True

        except Exception as e:
            self.logger.error(f"Failed to apply initial config: {e}")
            # Still mark as running so containerlab doesn't hang
            self.running = True


class VGW(vrnetlab.VR):
    """Aruba Virtual Gateway vrnetlab wrapper"""

    def __init__(self, hostname, username, password, conn_mode):
        super(VGW, self).__init__(username, password)
        self.vms = [VGW_vm(hostname, username, password, conn_mode)]


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Aruba VGW vrnetlab launcher")
    parser.add_argument(
        "--hostname", default="vgw", help="VM hostname (default: vgw)"
    )
    parser.add_argument(
        "--username", default="admin", help="Username (default: admin)"
    )
    parser.add_argument(
        "--password", default="admin", help="Password (default: admin)"
    )
    parser.add_argument(
        "--connection-mode",
        default="tc",
        help="Connection mode: tc or bridge (default: tc)",
    )
    parser.add_argument("--trace", action="store_true", help="Enable trace logging")

    args = parser.parse_args()

    LOG_FORMAT = "%(asctime)s: %(module)-10s %(levelname)-8s %(message)s"
    logging.basicConfig(format=LOG_FORMAT)
    logger = logging.getLogger()

    logger.setLevel(logging.DEBUG)
    if args.trace:
        logger.setLevel(TRACE_LEVEL_NUM)

    logger.info("Starting Aruba Virtual Gateway")

    vrnetlab.boot_delay()

    vr = VGW(
        args.hostname,
        args.username,
        args.password,
        args.connection_mode,
    )
    vr.start()

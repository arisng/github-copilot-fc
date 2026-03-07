#!/usr/bin/env python3
"""
Playwright CLI Configuration Manager

This script helps manage playwright-cli configuration files for complex automation workflows.
It can generate config files, validate existing ones, and provide templates for common use cases.
"""

import json
import argparse
import os
from typing import Dict, Any, Optional


class PlaywrightConfigManager:
    """Manages playwright-cli configuration files."""

    DEFAULT_CONFIG = {
        "browser": {
            "browserName": "chromium",
            "isolated": False,
            "launchOptions": {
                "headless": True
            },
            "contextOptions": {
                "viewport": {"width": 1280, "height": 720}
            }
        },
        "outputDir": "./output",
        "outputMode": "file",
        "timeouts": {
            "action": 5000,
            "navigation": 30000
        },
        "testIdAttribute": "data-testid"
    }

    @staticmethod
    def create_session_config(session_name: str, **kwargs) -> Dict[str, Any]:
        """Create a configuration for a specific session."""
        config = PlaywrightConfigManager.DEFAULT_CONFIG.copy()

        # Update with session-specific settings
        if 'browser' in kwargs:
            config['browser'].update(kwargs['browser'])
        if 'output_dir' in kwargs:
            config['outputDir'] = kwargs['output_dir']
        if 'headless' in kwargs:
            config['browser']['launchOptions']['headless'] = kwargs['headless']

        return config

    @staticmethod
    def create_testing_config() -> Dict[str, Any]:
        """Create a configuration optimized for testing scenarios."""
        config = PlaywrightConfigManager.DEFAULT_CONFIG.copy()
        config.update({
            "saveVideo": {"width": 1280, "height": 720},
            "console": {"level": "info"},
            "network": {
                "allowedOrigins": ["*"],
                "blockedOrigins": []
            }
        })
        return config

    @staticmethod
    def create_screenshot_config() -> Dict[str, Any]:
        """Create a configuration optimized for screenshot workflows."""
        config = PlaywrightConfigManager.DEFAULT_CONFIG.copy()
        config.update({
            "browser": {
                "browserName": "chromium",
                "launchOptions": {
                    "headless": True,
                    "args": ["--window-size=1920,1080"]
                },
                "contextOptions": {
                    "viewport": {"width": 1920, "height": 1080}
                }
            },
            "outputDir": "./screenshots"
        })
        return config

    @staticmethod
    def validate_config(config: Dict[str, Any]) -> bool:
        """Validate a configuration dictionary."""
        required_keys = ['browser']
        for key in required_keys:
            if key not in config:
                print(f"Missing required key: {key}")
                return False

        if 'browserName' not in config['browser']:
            print("Missing browser.browserName")
            return False

        valid_browsers = ['chromium', 'firefox', 'webkit']
        if config['browser']['browserName'] not in valid_browsers:
            print(f"Invalid browser name. Must be one of: {valid_browsers}")
            return False

        return True

    @staticmethod
    def save_config(config: Dict[str, Any], filename: str) -> None:
        """Save configuration to a JSON file."""
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2)
        print(f"Configuration saved to {filename}")

    @staticmethod
    def load_config(filename: str) -> Dict[str, Any]:
        """Load configuration from a JSON file."""
        with open(filename, 'r', encoding='utf-8') as f:
            return json.load(f)


def main():
    parser = argparse.ArgumentParser(description="Playwright CLI Configuration Manager")
    parser.add_argument('action', choices=['create', 'validate', 'template'],
                       help='Action to perform')
    parser.add_argument('--type', choices=['default', 'session', 'testing', 'screenshot'],
                       default='default', help='Configuration type')
    parser.add_argument('--output', '-o', help='Output file path')
    parser.add_argument('--input', '-i', help='Input file path for validation')
    parser.add_argument('--session-name', help='Session name for session config')

    args = parser.parse_args()

    manager = PlaywrightConfigManager()

    if args.action == 'create':
        if args.type == 'session':
            if not args.session_name:
                print("Session name required for session config")
                return
            config = manager.create_session_config(args.session_name)
        elif args.type == 'testing':
            config = manager.create_testing_config()
        elif args.type == 'screenshot':
            config = manager.create_screenshot_config()
        else:
            config = manager.DEFAULT_CONFIG

        output_file = args.output or f"playwright-{args.type}.json"
        manager.save_config(config, output_file)

    elif args.action == 'validate':
        if not args.input:
            print("Input file required for validation")
            return
        try:
            config = manager.load_config(args.input)
            if manager.validate_config(config):
                print("Configuration is valid")
            else:
                print("Configuration is invalid")
        except FileNotFoundError:
            print(f"File not found: {args.input}")
        except json.JSONDecodeError:
            print(f"Invalid JSON in file: {args.input}")

    elif args.action == 'template':
        print("Available configuration templates:")
        print("- default: Basic configuration")
        print("- session: Session-specific configuration")
        print("- testing: Optimized for testing scenarios")
        print("- screenshot: Optimized for screenshot workflows")
        print("\nExample usage:")
        print("python config_manager.py create --type testing --output my-config.json")


if __name__ == "__main__":
    main()
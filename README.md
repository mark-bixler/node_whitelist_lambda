# AWS Whitelisting IP's Lambda

This project takes lists of provided whitelisted IP's from **GitHub** & **Okta** and adds them to the appropriate  AWS EC2 Security Groups that are appropriately tagged to receive the IP rules.

## Getting Started

### Prerequisites

- AWS CLI
- Node.js
- Desired Security Group(s) tagged with either of the following entries:
  - **key**: "t_whitelist" **value**: "okta"
  - **key**: "t_whitelist" **value**: "github"

### Deployment

- Lambda running in AWS and invoked using various different methods
- Running locally by using [aws-lambda-local]( https://www.npmjs.com/package/aws-lambda-local).
  - See Medium Post about deployments using aws-lambda-local.

## Built With

- [Node.js 8.10](https://nodejs.org/en/) - The scripting engine used for AWS lambda

## Authors

- **Mark Bixler** - *Initial work* - [mark-bixler](https://github.com/mark-bixler)

See also the list of [contributors](https://github.com/your/project/contributors) who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](https://gist.github.com/PurpleBooth/LICENSE.md) file for details

## Acknowledgments

- For dedupe function: <https://www.jstips.co/en/javascript/deduplicate-an-array/>
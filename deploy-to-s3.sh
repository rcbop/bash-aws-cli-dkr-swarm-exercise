#!/bin/bash
S3BUCKET=${S3_BUCKET:-my-deployment-bucket}
git commit -am 'releasing version'
git archive -o provisioner-aws-swarm.zip HEAD
aws s3 cp ./provisioner-aws-swarm.zip s3://${S3BUCKET}/

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';

export class EcsWebAppStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const stackName = cdk.Stack.of(this).stackName;
    const vpcId = requiredContext(this, 'vpcId');
    const publicSubnetIds = requiredContext(this, 'publicSubnetIds')
      .split(',')
      .map((subnetId) => subnetId.trim())
      .filter(Boolean);
    const securityGroupId = requiredContext(this, 'securityGroupId');
    const containerImage = optionalContext(this, 'containerImage', 'nginx:latest');
    const instanceType = optionalContext(this, 'instanceType', 't3.micro');

    if (publicSubnetIds.length < 2) {
      throw new Error('Provide at least two public subnet IDs with -c publicSubnetIds=subnet-a,subnet-b');
    }

    const availabilityZones = cdk.Fn.getAzs();
    const vpc = ec2.Vpc.fromVpcAttributes(this, 'ImportedVpc', {
      vpcId,
      availabilityZones,
      publicSubnetIds
    });
    const publicSubnets = publicSubnetIds.map((subnetId, index) =>
      ec2.Subnet.fromSubnetAttributes(this, `PublicSubnet${index + 1}`, {
        subnetId,
        availabilityZone: cdk.Fn.select(index, availabilityZones)
      })
    );
    const securityGroup = ec2.SecurityGroup.fromSecurityGroupId(this, 'ImportedSecurityGroup', securityGroupId, {
      mutable: false
    });

    const repository = new ecr.Repository(this, 'WebAppRepository', {
      repositoryName: `${stackName}-webapp`,
      imageScanOnPush: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    const staticAssetsBucket = new s3.Bucket(this, 'StaticAssetsBucket', {
      bucketName: `${stackName}-static-assets-${this.account}-${this.region}`,
      blockPublicAccess: new s3.BlockPublicAccess({
        blockPublicAcls: true,
        blockPublicPolicy: false,
        ignorePublicAcls: true,
        restrictPublicBuckets: false
      }),
      encryption: s3.BucketEncryption.S3_MANAGED,
      objectOwnership: s3.ObjectOwnership.BUCKET_OWNER_ENFORCED,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });
    staticAssetsBucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'PublicReadStaticAssets',
      effect: iam.Effect.ALLOW,
      principals: [new iam.AnyPrincipal()],
      actions: ['s3:GetObject'],
      resources: [staticAssetsBucket.arnForObjects('assets/*')]
    }));

    const cluster = new ecs.Cluster(this, 'Cluster', {
      clusterName: `${stackName}-cluster`,
      vpc
    });

    const logGroup = new logs.LogGroup(this, 'LogGroup', {
      logGroupName: `/ecs/${stackName}/web`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    const ecsInstanceRole = new iam.Role(this, 'ECSInstanceRole', {
      roleName: `${stackName}-ecs-instance-role`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonEC2ContainerServiceforEC2Role')
      ]
    });

    const taskExecutionRole = new iam.Role(this, 'TaskExecutionRole', {
      roleName: `${stackName}-task-execution-role`,
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy')
      ]
    });

    const autoScalingGroup = new autoscaling.AutoScalingGroup(this, 'AutoScalingGroup', {
      autoScalingGroupName: `${stackName}-asg`,
      vpc,
      vpcSubnets: { subnets: publicSubnets },
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: ecs.EcsOptimizedImage.amazonLinux2(),
      minCapacity: 2,
      maxCapacity: 4,
      desiredCapacity: 2,
      healthChecks: autoscaling.HealthChecks.ec2({
        gracePeriod: cdk.Duration.seconds(300)
      }),
      role: ecsInstanceRole,
      securityGroup
    });
    cdk.Tags.of(autoScalingGroup).add('Name', `${stackName}-ecs-instance`, {
      applyToLaunchedInstances: true
    });

    const capacityProvider = new ecs.AsgCapacityProvider(this, 'CapacityProvider', {
      capacityProviderName: `${stackName}-capacity-provider`,
      autoScalingGroup,
      enableManagedScaling: true,
      targetCapacityPercent: 100,
      enableManagedTerminationProtection: false
    });
    cluster.addAsgCapacityProvider(capacityProvider);

    const taskDefinition = new ecs.Ec2TaskDefinition(this, 'TaskDefinition', {
      family: `${stackName}-web`,
      networkMode: ecs.NetworkMode.BRIDGE,
      executionRole: taskExecutionRole
    });
    const container = taskDefinition.addContainer('web', {
      image: ecs.ContainerImage.fromRegistry(containerImage),
      memoryLimitMiB: 256,
      environment: {
        STATIC_ASSET_BASE_URL: `https://${staticAssetsBucket.bucketName}.s3.${this.region}.amazonaws.com/assets`
      },
      logging: ecs.LogDrivers.awsLogs({
        logGroup,
        streamPrefix: 'web'
      })
    });
    container.addPortMappings({
      containerPort: 80,
      hostPort: 80,
      protocol: ecs.Protocol.TCP
    });

    const loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'LoadBalancer', {
      loadBalancerName: `${stackName}-alb`,
      vpc,
      internetFacing: true,
      securityGroup,
      vpcSubnets: { subnets: publicSubnets }
    });

    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      targetGroupName: `${stackName}-tg`,
      vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.INSTANCE,
      healthCheck: {
        enabled: true,
        path: '/',
        protocol: elbv2.Protocol.HTTP,
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        healthyHttpCodes: '200-399'
      }
    });

    const listener = loadBalancer.addListener('Listener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup]
    });

    const service = new ecs.Ec2Service(this, 'Service', {
      serviceName: `${stackName}-service`,
      cluster,
      taskDefinition,
      desiredCount: 2,
      capacityProviderStrategies: [
        {
          capacityProvider: capacityProvider.capacityProviderName,
          weight: 1
        }
      ],
      placementStrategies: [
        ecs.PlacementStrategy.spreadAcross('attribute:ecs.availability-zone'),
        ecs.PlacementStrategy.spreadAcross('instanceId')
      ],
      circuitBreaker: {
        rollback: true
      },
      minHealthyPercent: 50,
      maxHealthyPercent: 200
    });
    service.attachToApplicationTargetGroup(targetGroup);
    service.node.addDependency(listener);
    service.node.addDependency(capacityProvider);

    new cdk.CfnOutput(this, 'LoadBalancerDNSName', {
      description: 'DNS name for the application load balancer.',
      value: loadBalancer.loadBalancerDnsName
    });
    new cdk.CfnOutput(this, 'ApplicationURL', {
      description: 'HTTP URL for the deployed web application.',
      value: `http://${loadBalancer.loadBalancerDnsName}`
    });
    new cdk.CfnOutput(this, 'ECSClusterName', {
      description: 'ECS cluster name.',
      value: cluster.clusterName
    });
    new cdk.CfnOutput(this, 'ECSServiceName', {
      description: 'ECS service name.',
      value: service.serviceName
    });
    new cdk.CfnOutput(this, 'ECRRepositoryUri', {
      description: 'ECR repository URI for the web app image.',
      value: repository.repositoryUri
    });
    new cdk.CfnOutput(this, 'StaticAssetsBucketName', {
      description: 'S3 bucket name for static web assets.',
      value: staticAssetsBucket.bucketName
    });
    new cdk.CfnOutput(this, 'StaticAssetBaseURL', {
      description: 'Public base URL for S3 static assets.',
      value: `https://${staticAssetsBucket.bucketName}.s3.${this.region}.amazonaws.com/assets`
    });
  }
}

function requiredContext(scope: Construct, key: string): string {
  const value = scope.node.tryGetContext(key);
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`Missing required CDK context value: -c ${key}=...`);
  }
  return value.trim();
}

function optionalContext(scope: Construct, key: string, defaultValue: string): string {
  const value = scope.node.tryGetContext(key);
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : defaultValue;
}

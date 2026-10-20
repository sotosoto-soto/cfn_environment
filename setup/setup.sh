#!/usr/bin/env bash

set -e
export AWS_CLI_FILE_ENCODING=UTF-8

if [[ "$#" -lt 2 ]]; then
    echo "エラー: 引数が足りません。"
    echo "使い方: $0 [profile] [up|stop|down|create_sshkey]"
    exit 1
fi

PROFILE="$1"
ACTION="$2"

# region、stack_name、keynameの初期値
REGION="ap-northeast-1"
STACKNAME="cfn-practice-stack"
KEYNAME="cfn-practice-key"

if [[ "$ACTION" == "down" ]]; then
    echo "EC2の削除を行います。"

    # CloudFormationスタックを削除
    aws cloudformation delete-stack \
        --stack-name "$STACKNAME" \
        --region "$REGION" \
        --profile "$PROFILE"

    aws cloudformation wait stack-delete-complete \
        --stack-name "$STACKNAME" \
        --region "$REGION" \
        --profile "$PROFILE"

    echo "EC2の削除が完了しました。"

elif [[ "$ACTION" == "up" ]]; then
    echo "EC2の作成を行います。"

    # 接続元IPを取得
    MY_IP=$(curl -4 -fsS https://checkip.amazonaws.com | tr -d '\r\n')

    if [[ -z "$MY_IP" ]]; then
        echo "エラー: 接続元IPを取得できませんでした。"
        exit 1
    fi

    echo "接続元IP: $MY_IP"

    # CloudFormationでEC2を作成
    aws cloudformation deploy \
        --template-file "./setup.yml" \
        --stack-name "$STACKNAME" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --parameter-overrides SSHSourceCidr="${MY_IP}/32"

    # パブリックIPを取得
    PUBLIC_IP=$(aws cloudformation describe-stacks \
        --stack-name "$STACKNAME" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "Stacks[0].Outputs[?OutputKey=='PublicIp'].OutputValue | [0]" \
        --output text)

    echo "EC2 Public IP: $PUBLIC_IP"
    echo "EC2の作成が完了しました。"
<<<<<<< Updated upstream
=======
    echo ""
    echo "以下を ~/.ssh/config に追記してください。"
    echo "-----"
    echo "Host $KEYNAME"
    echo "    HostName $PUBLIC_DNS"
    echo "    User ec2-user"
    echo "    Port 22222"
    echo "    IdentityFile ~/.ssh/$KEYNAME.pem"
    echo "    ProxyCommand connect -H プロキシサーバ:ポート番号 %h %p"
    echo "-----"
>>>>>>> Stashed changes

elif [[ "$ACTION" == "stop" ]]; then
    echo "EC2の停止を行います。"

    # CloudFormationスタックに含まれるEC2インスタンスIDを取得
    INSTANCE_IDS_TEXT=$(aws cloudformation list-stack-resources \
        --stack-name "$STACKNAME" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "StackResourceSummaries[?ResourceType=='AWS::EC2::Instance'].PhysicalResourceId" \
        --output text)

    if [[ -z "$INSTANCE_IDS_TEXT" || "$INSTANCE_IDS_TEXT" == "None" ]]; then
        echo "停止対象のEC2インスタンスが見つかりません。"
        exit 1
    fi

    # 空白・タブ区切りのインスタンスIDを配列に変換
    read -r -a INSTANCE_IDS <<< "$INSTANCE_IDS_TEXT"

    echo "停止対象: ${INSTANCE_IDS[*]}"

    aws ec2 stop-instances \
        --instance-ids "${INSTANCE_IDS[@]}" \
        --region "$REGION" \
        --profile "$PROFILE"

    echo "EC2インスタンスの停止を待っています..."

    aws ec2 wait instance-stopped \
        --instance-ids "${INSTANCE_IDS[@]}" \
        --region "$REGION" \
        --profile "$PROFILE"

    echo "EC2インスタンスを停止しました。"

elif [[ "$ACTION" == "create_sshkey" ]]; then
    echo "SSH鍵の作成を行います。"

    aws ec2 create-key-pair \
        --key-name "$KEYNAME" \
        --key-type rsa \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'KeyMaterial' \
        --output text > "$HOME/.ssh/$KEYNAME.pem"

    chmod 400 "$HOME/.ssh/$KEYNAME.pem"

    echo "SSH鍵の作成が完了しました。"
    echo "秘密鍵は $HOME/.ssh/$KEYNAME.pem です。"

else
    echo "エラー: 第2引数は [up|stop|down|create_sshkey] を指定してください。"
    exit 1
fi
